// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PerpVault} from "../src/PerpVault.sol";

contract PerpVaultScript is Script {
    PerpVault public perpVault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        perpVault = new PerpVault();

        vm.stopBroadcast();
    }
}
