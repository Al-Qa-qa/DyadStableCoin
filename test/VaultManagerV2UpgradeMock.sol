// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DNft}            from "../src/core/DNft.sol";
import {Dyad}            from "../src/core/Dyad.sol";
import {VaultLicenser}   from "../src/core/VaultLicenser.sol";
import {Vault}           from "../src/core/Vault.sol";
import {IVaultManager}   from "../src/interfaces/IVaultManager.sol";

import {FixedPointMathLib}  from "@solmate/src/utils/FixedPointMathLib.sol";
import {ERC20}              from "@solmate/src/tokens/ERC20.sol";
import {SafeTransferLib}    from "@solmate/src/utils/SafeTransferLib.sol";

import {EnumerableSet}      from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable}    from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @custom:oz-upgrades-from src/core/VaultManagerV2.sol:VaultManagerV2
 */ 
contract VaultManagerV2UpgradeMock is IVaultManager, UUPSUpgradeable, OwnableUpgradeable {
  using EnumerableSet     for EnumerableSet.AddressSet;
  using FixedPointMathLib for uint;
  using SafeTransferLib   for ERC20;

  uint public constant MAX_VAULTS         = 6;
  uint public constant MIN_COLLAT_RATIO   = 1.5e18; // 150% // Collaterization
  uint public constant LIQUIDATION_REWARD = 0.2e18; //  20%

  DNft          public dNft;
  Dyad          public dyad;
  VaultLicenser public vaultLicenser;

  mapping (uint => EnumerableSet.AddressSet) internal vaults; 
  mapping (uint/* id */ => uint/* block */)  public   lastDeposit;

  modifier isDNftOwner(uint id) {
    if (dNft.ownerOf(id) != msg.sender) revert NotOwner();    _;
  }
  modifier isValidDNft(uint id) {
    if (dNft.ownerOf(id) == address(0)) revert InvalidDNft(); _;
  }

  /**
   * @notice Prevents implementation contract from being initialized 
   * @dev See: https://docs.openzeppelin.com/contracts/4.x/api/proxy#Initializable-_disableInitializers--
   * @custom:oz-upgrades-unsafe-allow constructor
   */
  constructor() { _disableInitializers(); }

  function initialize(
    address          _dNft
    // Dyad          _dyad,
    // VaultLicenser _vaultLicenser
  ) 
    public 
      onlyOwner
  {
    dNft          = DNft(_dNft);
    // dyad          = _dyad;
    // vaultLicenser = _vaultLicenser;

    // __Ownable_init(msg.sender);
    // __UUPSUpgradeable_init();
  }

  /// @inheritdoc IVaultManager
  function add(
      uint    id,
      address vault
  ) 
    external
      // isDNftOwner(id)
  {
    // if (!vaultLicenser.isLicensed(vault))   revert VaultNotLicensed();
    // if ( vaults[id].length() >= MAX_VAULTS) revert TooManyVaults();
    // if (!vaults[id].add(vault))             revert VaultAlreadyAdded();
    emit Added(id, vault);
  }

  /// @inheritdoc IVaultManager
  function remove(
      uint    id,
      address vault
  ) 
    external
      isDNftOwner(id)
  {
    if (Vault(vault).id2asset(id) > 0) revert VaultHasAssets();
    if (!vaults[id].remove(vault))     revert VaultNotAdded();
    emit Removed(id, vault);
  }

  /// @inheritdoc IVaultManager
  function deposit(
    uint    id,
    address vault,
    uint    amount
  ) 
    external 
      isDNftOwner(id)
  {
    lastDeposit[id] = block.number;
    Vault _vault = Vault(vault);
    _vault.asset().safeTransferFrom(msg.sender, address(vault), amount);
    _vault.deposit(id, amount);
  }

  /// @inheritdoc IVaultManager
  function withdraw(
    uint    id,
    address vault,
    uint    amount,
    address to
  ) 
    public
      isDNftOwner(id)
  {
    if (lastDeposit[id] == block.number) revert CanNotWithdrawInSameBlock();
    Vault _vault = Vault(vault);
    _vault.withdraw(id, to, amount); // changes `exo` or `kero` value and `cr`
    (uint exoValue, uint keroValue) = getVaultsValues(id);
    uint mintedDyad = dyad.mintedDyad(id);
    if (exoValue < mintedDyad) revert NotEnoughExoCollat();
    uint cr = _collatRatio(mintedDyad, exoValue+keroValue);
    if (cr < MIN_COLLAT_RATIO) revert CrTooLow(); 
  }

  /// @inheritdoc IVaultManager
  function mintDyad(
    uint    id,
    uint    amount,
    address to
  )
    external 
      isDNftOwner(id)
  {
    dyad.mint(id, to, amount); // changes `mintedDyad` and `cr`
    (uint exoValue, uint keroValue) = getVaultsValues(id);
    uint mintedDyad = dyad.mintedDyad(id);
    if (exoValue < mintedDyad) revert NotEnoughExoCollat();
    uint cr = _collatRatio(mintedDyad, exoValue+keroValue);
    if (cr < MIN_COLLAT_RATIO) revert CrTooLow(); 
    emit MintDyad(id, amount, to);
  }

  /// @inheritdoc IVaultManager
  function burnDyad(
    uint id,
    uint amount
  ) 
    external 
      isValidDNft(id)
  {
    dyad.burn(id, msg.sender, amount);
    emit BurnDyad(id, amount, msg.sender);
  }

  function redeemDyad(
    uint    id,
    address vault,
    uint    amount,
    address to
  )
    external 
      isDNftOwner(id)
    returns (uint) { 
      dyad.burn(id, msg.sender, amount);
      Vault _vault = Vault(vault);
      uint asset = amount 
                    * 10**_vault.oracle().decimals() 
                    / _vault.assetPrice();
      withdraw(id, vault, asset, to);
      emit RedeemDyad(id, vault, amount, to);
      return asset;
  }

  function liquidate(
    uint id,
    uint to,
    uint amount
  ) 
    external 
      isValidDNft(id)
      isValidDNft(to)
    {
      // if (collatRatio(id) >= MIN_COLLAT_RATIO) revert CrTooHigh();
      // uint debt = dyad.mintedDyad(id);
      // dyad.burn(id, msg.sender, amount); // changes `debt` and `cr`

      // lastDeposit[to] = block.number; // `move` acts like a deposit

      // uint totalValue  = getTotalValue(id);
      // uint reward_rate = amount
      //                     .divWadDown(debt)
      //                     .mulWadDown(LIQUIDATION_REWARD);

      // uint numberOfVaults = vaults[id].length();
      // for (uint i = 0; i < numberOfVaults; i++) {
      //     Vault vault = Vault(vaults[id].at(i));
      //     uint value       = vault.getUsdValue(id);
      //     uint share       = value.divWadDown(totalValue);
      //     uint amountShare = share.mulWadDown(amount);
      //     uint valueToMove = amountShare + amountShare.mulWadDown(reward_rate);
      //     uint cappedValue = valueToMove > value ? value : valueToMove;
      //     uint asset = cappedValue 
      //                    * (10**(vault.oracle().decimals() + vault.asset().decimals())) 
      //                    / vault.assetPrice() 
      //                    / 1e18;

      //     vault.move(id, to, asset);
      // }

      emit Liquidate(id, msg.sender, to);
  }

  function collatRatio(
    uint id
  )
    public 
    view
    returns (uint) {
      uint mintedDyad = dyad.mintedDyad(id);
      uint totalValue = getTotalValue(id);
      return _collatRatio(mintedDyad, totalValue);
  }

  /// @dev Why do we have the same function with different arguments?
  ///      Sometimes we can re-use the `mintedDyad` and `totalValue` values,
  ///      Calculating them is expensive, so we can re-use the cached values.
  function _collatRatio(
    uint mintedDyad, 
    uint totalValue // in USD
  )
    internal 
    pure
    returns (uint) {
      if (mintedDyad == 0) return type(uint).max;
      return totalValue.divWadDown(mintedDyad);
  }

  function getTotalValue( // in USD
    uint id
  ) 
    public 
    view
    returns (uint) {
      (uint exoValue, uint keroValue) = getVaultsValues(id);
      return exoValue + keroValue;
  }

  function getVaultsValues( // in USD
    uint id
  ) 
    public 
    view
    returns (
      uint exoValue, // exo := exogenous (non-kerosene)
      uint keroValue
    ) {
      uint numberOfVaults = vaults[id].length(); 

      for (uint i = 0; i < numberOfVaults; i++) {
        Vault vault = Vault(vaults[id].at(i));
        if (vaultLicenser.isLicensed(address(vault))) {
          if (vaultLicenser.isKerosene(address(vault))) {
            keroValue += vault.getUsdValue(id);
          } else {
            exoValue  += vault.getUsdValue(id);
          }
        }
      }
  }

  // ----------------- MISC ----------------- //
  function getVaults(
    uint id
  ) 
    external 
    view 
    returns (address[] memory) {
      return vaults[id].values();
  }

  function hasVault(
    uint    id,
    address vault
  ) 
    external 
    view 
    returns (bool) {
      return vaults[id].contains(vault);
  }

  // ----------------- UPGRADABILITY ----------------- //
  function _authorizeUpgrade(address newImplementation) 
    internal 
    override 
  {
    require(msg.sender == owner(), "VaultManagerV2: not owner");
  }
}
