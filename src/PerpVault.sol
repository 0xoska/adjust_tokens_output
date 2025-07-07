// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Uniswap v4-core imports
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencyLibraryExt} from "src/libraries/Currency.sol";

contract PerpVault {
    using CurrencyLibrary for Currency;
    using CurrencyLibraryExt for Currency;

    uint8 private constant feeRate = 10;

    function getTokenAmountOut(
        bool isBuy,
        Currency token0, 
        Currency token1, 
        uint256 amountIn,
        uint256 alpPrice
    ) external view returns (uint256 amountOut) {
        (, uint8 tokenDecimals) = CurrencyLibraryExt.tryGetERC20Decimals(token1);
        if(isBuy){
            uint256 bigAmountOut = amountIn / 10000 * (10000 - feeRate) / (10 ** tokenDecimals) * alpPrice;
            amountOut = CurrencyLibraryExt._adjustTokenDecimals(
                true, 
                token0, 
                token1, 
                bigAmountOut
            );
        }else{
            uint256 bigAmountOut = amountIn * alpPrice / 10 ** tokenDecimals;
            uint256 includeFeeAmountOut = CurrencyLibraryExt._adjustTokenDecimals(
                false, 
                token0, 
                token1, 
                bigAmountOut
            );
            amountOut = includeFeeAmountOut * (10000 - feeRate) / 10000;
        }
    }

    
}
