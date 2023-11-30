// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {VaultManager}  from "./VaultManager.sol";
import {IDNft}         from "../interfaces/IDNft.sol";
import {IVault}        from "../interfaces/IVault.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

import {SafeCast}          from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeTransferLib}   from "@solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {ERC20}             from "@solmate/src/tokens/ERC20.sol";

contract Vault is IVault {
  using SafeTransferLib   for ERC20;
  using SafeCast          for int;
  using FixedPointMathLib for uint;

  VaultManager  public immutable vaultManager;
  ERC20         public immutable asset;
  IAggregatorV3 public immutable oracle;

  mapping(uint => uint) public id2asset;

  modifier onlyVaultManager() {
    if (msg.sender != address(vaultManager)) revert NotVaultManager();
    _;
  }

  constructor(
    VaultManager  _vaultManager,
    ERC20         _asset,
    IAggregatorV3 _oracle
  ) {
    vaultManager   = _vaultManager;
    asset          = _asset;
    oracle         = _oracle;
  }

  function deposit(
    uint id,
    uint amount
  )
    external 
      onlyVaultManager
  {
    id2asset[id] += amount;
    emit Deposit(id, amount);
  }

  function withdraw(
    uint    id,
    address to,
    uint    amount
  ) 
    external 
      onlyVaultManager
  {
    id2asset[id] -= amount;
    asset.safeTransfer(to, amount); 
    emit Withdraw(id, to, amount);
  }

  function move(
    uint from,
    uint to,
    uint amount
  )
    external
      onlyVaultManager
  {
    id2asset[from] -= amount;
    id2asset[to]   += amount;
    emit Move(from, to, amount);
  }

  function getUsdValue(
    uint id
  )
    external
    view 
    returns (uint) {
      return id2asset[id] * assetPrice() 
              * 1e18 
              / 10**oracle.decimals() 
              / 10**asset.decimals();
  }

  function assetPrice() 
    public 
    view 
    returns (uint) {
      (
        uint80 roundID,
        int256 price,
        , 
        uint256 timeStamp, 
        uint80 answeredInRound
      ) = oracle.latestRoundData();
      if (timeStamp == 0)            revert IncompleteRound();
      if (answeredInRound < roundID) revert StaleData();
      return price.toUint256();
  }
}
