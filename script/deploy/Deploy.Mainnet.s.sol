// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {Parameters} from "../../src/params/Parameters.sol";

contract DeployMainnet is Script, Parameters {
  function run() public {
    new DeployBase().deploy(
      MAINNET_OWNER,
      MAINNET_DNFT,
      MAINNET_WETH,
      MAINNET_WETH_ORACLE,
      MAINNET_FEE, 
      MAINNET_FEE_RECIPIENT
    );
  }
}
