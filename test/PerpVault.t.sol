// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PerpVault} from "../src/PerpVault.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "@solmate/src/test/utils/mocks/MockERC20.sol";

contract PerpVaultTest is Test {

    PerpVault public perpVault;

    address public user1;
    address public user2;

    MockERC20 public mockBaseToken;
    MockERC20 public mockUSDCToken;

    Currency public baseTokenCurrency;
    Currency public usdcTokenCurrency;

    function setUp() public {
        //deploy
        perpVault = new PerpVault();

        // Setup addresses
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        mockBaseToken = new MockERC20("Base Token", "Base", 18);
        mockUSDCToken = new MockERC20("USDC Token", "USDC", 6);

        // Setup base token currency
        baseTokenCurrency = Currency.wrap(address(mockBaseToken)); 
        usdcTokenCurrency = Currency.wrap(address(mockUSDCToken)); 

    }

    function test_GetTokenAmountOut() public {


        //buy input 100 base(sell base get 200 * ( 10000 -10)usdc)
        uint256 amountIn1 = 100 * 10 ** 18;
        //base : usdc = 2 usdc 
        uint256 alpPrice1 = 2 * 10 ** 6;
        uint256 usdcAmount = perpVault.getTokenAmountOut(true, baseTokenCurrency, usdcTokenCurrency, amountIn1, alpPrice1);
        console.log("usdcAmount:", usdcAmount);

        //sell input 100 usdc(sell usdc get 50 * ( 10000 -10)base)
        uint256 amountIn2 = 100 * 10 ** 6;
        // usdc : base = 0.5 usdc
        uint256 alpPrice2 = 5 * 10 ** 5;
        uint256 baseAmount = perpVault.getTokenAmountOut(false, baseTokenCurrency, usdcTokenCurrency, amountIn2, alpPrice2);
        console.log("baseAmount:", baseAmount);
    }

}
