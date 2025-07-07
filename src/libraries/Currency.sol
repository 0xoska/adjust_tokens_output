// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title CurrencyLibrary
/// @dev This library extends CurrencyLibrary to handle ERC20 transferFrom operations
library CurrencyLibraryExt {
    /// @notice Additional context for ERC-7751 wrapped error when an ERC20 transfer fails
    error NativeTransferFromFailed();
    /// @notice Additional context for ERC-7751 wrapped error when an ERC20 transfer fails
    error ERC20TransferFromFailed();
    /// @notice Verify whether it is the correct ERC20 token
    error InvalidToken();

    // /// @notice Transfers tokens from one address to another using transferFrom
    // /// @param currency The currency to transfer
    // /// @param from The address to transfer from
    // /// @param to The address to transfer to
    // /// @param amount The amount to transfer

    /// ref: https://github.com/aave/aave-v3-core/blob/master/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol
    /// @dev Wrapper around a call to the ERC20 function `transferFrom` that
    /// reverts also when the token returns `false`.
    function transferFrom(Currency currency, address from, address to, uint256 value) internal {
        if (currency.isAddressZero()) {
            // if to is address(this), check if msg.value is equal to value
            if (to == address(this) && msg.value != value) {
                CustomRevert.bubbleUpAndRevertWith(from, bytes4(0), NativeTransferFromFailed.selector);
            }
            // if from is address(this), perform a native transfer
            if (from == address(this)) {
                bool success;
                assembly ("memory-safe") {
                    // Transfer the ETH and revert if it fails.
                    success := call(gas(), to, value, 0, 0, 0, 0)
                }
                // revert with NativeTransferFailed, containing the bubbled up error as an argument
                if (success) {
                    return;
                } else {
                    CustomRevert.bubbleUpAndRevertWith(to, bytes4(0), NativeTransferFromFailed.selector);
                }
            }
            // only support above two cases
            CustomRevert.bubbleUpAndRevertWith(from, bytes4(0), NativeTransferFromFailed.selector);
        } else if (msg.value != 0) {
            CustomRevert.bubbleUpAndRevertWith(from, bytes4(0), NativeTransferFromFailed.selector);
        }

        bytes4 selector_ = IERC20(Currency.unwrap(currency)).transferFrom.selector;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freeMemoryPointer := mload(0x40)
            mstore(freeMemoryPointer, selector_)
            mstore(add(freeMemoryPointer, 4), and(from, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freeMemoryPointer, 36), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freeMemoryPointer, 68), value)

            if iszero(call(gas(), currency, 0, freeMemoryPointer, 100, 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        if (!getLastTransferResult(IERC20(Currency.unwrap(currency)))) {
            CustomRevert.bubbleUpAndRevertWith(
                Currency.unwrap(currency), IERC20Minimal.transferFrom.selector, ERC20TransferFromFailed.selector
            );
        }
    }

    /// @dev Verifies that the last return was a successful `transfer*` call.
    /// This is done by checking that the return data is either empty, or
    /// is a valid ABI encoded boolean.
    function getLastTransferResult(IERC20 token) private view returns (bool success) {
        // NOTE: Inspecting previous return data requires assembly. Note that
        // we write the return data to memory 0 in the case where the return
        // data size is 32, this is OK since the first 64 bytes of memory are
        // reserved by Solidy as a scratch space that can be used within
        // assembly blocks.
        // <https://docs.soliditylang.org/en/v0.7.6/internals/layout_in_memory.html>
        // solhint-disable-next-line no-inline-assembly
        assembly {
            /// @dev Revert with an ABI encoded Solidity error with a message
            /// that fits into 32-bytes.
            ///
            /// An ABI encoded Solidity error has the following memory layout:
            ///
            /// ------------+----------------------------------
            ///  byte range | value
            /// ------------+----------------------------------
            ///  0x00..0x04 |        selector("Error(string)")
            ///  0x04..0x24 |      string offset (always 0x20)
            ///  0x24..0x44 |                    string length
            ///  0x44..0x64 | string value, padded to 32-bytes
            function revertWithMessage(length, message) {
                mstore(0x00, "\x08\xc3\x79\xa0")
                mstore(0x04, 0x20)
                mstore(0x24, length)
                mstore(0x44, message)
                revert(0x00, 0x64)
            }

            switch returndatasize()
            // Non-standard ERC20 transfer without return.
            case 0 {
                // NOTE: When the return data size is 0, verify that there
                // is code at the address. This is done in order to maintain
                // compatibility with Solidity calling conventions.
                // <https://docs.soliditylang.org/en/v0.7.6/control-structures.html#external-function-calls>
                if iszero(extcodesize(token)) { revertWithMessage(20, "GPv2: not a contract") }

                success := 1
            }
            // Standard ERC20 transfer returning boolean success value.
            case 32 {
                returndatacopy(0, 0, returndatasize())

                // NOTE: For ABI encoding v1, any non-zero value is accepted
                // as `true` for a boolean. In order to stay compatible with
                // OpenZeppelin's `SafeERC20` library which is known to work
                // with the existing ERC20 implementation we care about,
                // make sure we return success for any non-zero return value
                // from the `transfer*` call.
                success := iszero(iszero(mload(0)))
            }
            default { revertWithMessage(31, "GPv2: malformed transfer result") }
        }
    }

    function tryGetERC20Name(Currency currency) internal view returns (bool, string memory) {
        (bool success, bytes memory encodedName) =
            Currency.unwrap(currency).staticcall(abi.encodeCall(IERC20Metadata.name, ()));
        if (success && encodedName.length >= 32) {
            string memory returnedName = abi.decode(encodedName, (string));
            if (bytes(returnedName).length > 0) {
                return (true, returnedName);
            }
        }
        return (false, "");
    }

    function tryGetERC20Symbol(Currency currency) internal view returns (bool, string memory) {
        (bool success, bytes memory encodedSymbol) =
            Currency.unwrap(currency).staticcall(abi.encodeCall(IERC20Metadata.symbol, ()));
        if (success && encodedSymbol.length >= 32) {
            string memory returnedSymbol = abi.decode(encodedSymbol, (string));
            if (bytes(returnedSymbol).length > 0) {
                return (true, returnedSymbol);
            }
        }
        return (false, "");
    }

    function tryGetERC20Decimals(Currency currency) internal view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) =
            Currency.unwrap(currency).staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    // ///@dev     .The quantity operation between user token0 and token1
    // ///@param   _isToken0In  .If it is true, the input quantity is token0; otherwise, it is token1
    // ///@param   _token0  .Token 0 address
    // ///@param   _token1  . Token 1 address
    // ///@param   amountIn  .Operation input amount
    // ///@return  amountOut  . Output another number of tokens
    function _adjustTokenDecimals(
        bool _isToken0In,
        Currency _token0,
        Currency _token1,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut) {
        (bool state0, uint8 token0Decimals) = tryGetERC20Decimals(_token0);
        (bool state1, uint8 token1Decimals) = tryGetERC20Decimals(_token1);
        if(state0 && state1){
            amountOut = _tokensDecimalsOperation(
                _isToken0In, 
                token0Decimals, 
                token1Decimals, 
                _amountIn
            );
        }else {
            revert InvalidToken();
        }
    }

    // ///@dev     .The quantity operation between user token0 and token1
    // ///@param   _isToken0In  .If it is true, the input quantity is token0; otherwise, it is token1
    // ///@param   _token0Decimals  .token 0 decimals
    // ///@param   _token1Decimals  . token 1 decimals
    // ///@param   amountIn  .Operation input amount
    // ///@return  amountOut  . Output another number of tokens
    function _tokensDecimalsOperation(
        bool _isToken0In,
        uint8 _token0Decimals,
        uint8 _token1Decimals,
        uint256 _amountIn
    ) internal pure returns (uint256 amountOut) {
        if (_amountIn > 0) {
            if (_token0Decimals > 0 && _token1Decimals > 0) {
                if (_token0Decimals == _token1Decimals) {
                    amountOut = _amountIn;
                } else if (_token0Decimals > _token1Decimals) {
                    if (_isToken0In) {
                        //out token1
                        amountOut = _amountIn / 10 ** (_token0Decimals - _token1Decimals);
                    } else {
                        //out token0
                        amountOut = _amountIn * 10 ** (_token0Decimals - _token1Decimals);
                    }
                } else {
                    if (_isToken0In) {
                        //out token1
                        amountOut = _amountIn * 10 ** (_token1Decimals - _token0Decimals);
                    } else {
                        // out token0
                        amountOut = _amountIn / 10 ** (_token1Decimals - _token0Decimals);
                    }
                }
            } else {
                revert InvalidToken();
            }
        }
    }
}
