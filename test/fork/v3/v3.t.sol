// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import {BaseTestV3} from "./BaseV3.sol";
import {Licenser} from "../../../src/core/Licenser.sol";
import {VaultManagerV2} from "../../../src/core/VaultManagerV2.sol";
import {IVaultManager} from "../../../src/interfaces/IVaultManager.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * Notes: Fork test 
 *   - block 19621640
 *   - $3,545.56 / ETH
 */
contract V3Test is BaseTestV3 {
    function test_LicenseVaultManager() public {
        Licenser licenser = Licenser(MAINNET_VAULT_MANAGER_LICENSER);
        vm.prank(MAINNET_OWNER);
        licenser.add(address(contracts.vaultManager));
    }

    function test_MintDNftOwner0() public mintAlice0 {
        assertEq(contracts.dNft.balanceOf(alice), 1);
    }

    function test_MintDNftOwner1() public mintBob0 {
        assertEq(contracts.dNft.balanceOf(bob), 1);
    }

    function test_Mint2DNfts() public mintAlice0 mintAlice1 {
        assertEq(contracts.dNft.balanceOf(alice), 2);
    }

    function test_AddVault() public mintAlice0 addVault(alice0, contracts.ethVault) {
        address firstVault = contracts.vaultManager.getVaults(alice0)[0];
        assertEq(firstVault, address(contracts.ethVault));
    }

    function test_Add2Vaults()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        addVault(alice0, contracts.wstEth)
    {
        address[] memory vaults = contracts.vaultManager.getVaults(alice0);
        assertEq(vaults[0], address(contracts.ethVault));
        assertEq(vaults[1], address(contracts.wstEth));
    }

    function test_Deposit()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
    {
        assertEq(contracts.ethVault.id2asset(alice0), 100 ether);
    }

    function test_DepositKerosene()
        public
        mintAlice0
        addVault(alice0, contracts.keroseneVault)
        deposit(alice0, contracts.keroseneVault, 200e18)
    {
        assertEq(contracts.keroseneVault.id2asset(alice0), 200e18);
    }

    function test_DepositBob()
        public
        mintBob0
        addVault(bob0, contracts.ethVault)
        deposit(bob0, contracts.ethVault, 100 ether)
    {
        assertEq(contracts.ethVault.id2asset(bob0), 100 ether);
    }

    modifier burnDyad(uint256 id, uint256 amount) {
        contracts.vaultManager.burnDyad(id, amount);
        _;
    }

    function test_BurnAllDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(10 ether))
        burnDyad(alice0, _ethToUSD(10 ether))
    {
        assertEq(getMintedDyad(alice0), 0);
        assertEq(contracts.dyad.balanceOf(address(this)), 0);
    }

    function test_BurnSomeDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(10 ether))
        burnDyad(alice0, _ethToUSD(1 ether))
    {
        assertEq(getMintedDyad(alice0), _ethToUSD(10 ether - 1 ether));
    }

    function test_BurnSomeDyadAndMintSomeDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(10 ether))
        burnDyad(alice0, _ethToUSD(1 ether))
        mintDyad(alice0, _ethToUSD(1 ether))
    {
        assertEq(getMintedDyad(alice0), _ethToUSD(10 ether - 1 ether + 1 ether));
    }

    modifier redeemDyad(uint256 id, IVault vault, uint256 amount) {
        contracts.vaultManager.redeemDyad(id, address(vault), amount, address(this));
        _;
    }

    function test_RedeemDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(10 ether))
        skipBlock(1)
        redeemDyad(alice0, contracts.ethVault, _ethToUSD(10 ether))
    {
        assertTrue(contracts.ethVault.id2asset(alice0) < 100 ether);
    }

    modifier withdraw(uint256 id, IVault vault, uint256 amount) {
        contracts.vaultManager.withdraw(id, address(vault), amount, address(this));
        _;
    }

    /// @dev All collateral can be withdrawn if no DYAD was minted
    function test_WithdrawEverythingWithoutMintingDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        skipBlock(1)
        withdraw(alice0, contracts.ethVault, 100 ether)
    {
        assertEq(contracts.ethVault.id2asset(alice0), 0 ether);
    }

    function test_WithdrawSomeEthAfterMintingDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        skipBlock(1)
        mintDyad(alice0, _ethToUSD(2 ether))
        skipBlock(1)
        withdraw(alice0, contracts.ethVault, 22 ether)
    {
        assertEq(contracts.ethVault.id2asset(alice0), 100 ether - 22 ether);
    }

    function test_WithdrawAllKerosene()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        addVault(alice0, contracts.keroseneVault)
        deposit(alice0, contracts.keroseneVault, 200e18)
        skipBlock(1)
        withdraw(alice0, contracts.keroseneVault, 200e18)
    {
        assertEq(contracts.keroseneVault.id2asset(alice0), 0);
    }

    /// @dev Test fails because the withdarwl of 1 Ether will put it under the CR
    ///      limit.
    function test_FailWithdrawCrTooLow()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 10 ether)
        skipBlock(1) // is not actually needed
        mintDyad(alice0, _ethToUSD(6.55 ether))
        skipBlock(1)
        nextCallFails(IVaultManager.CrTooLow.selector)
        withdraw(alice0, contracts.ethVault, 1 ether)
    {}

    function test_FailWithdrawNotEnoughExoCollateral()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 10 ether)
        skipBlock(1) // is not actually needed
        mintDyad(alice0, _ethToUSD(6.55 ether))
        skipBlock(1)
        nextCallFails(IVaultManager.NotEnoughExoCollat.selector)
        withdraw(alice0, contracts.ethVault, 5 ether)
    {}

    /// @dev Test fails because deposit and withdraw are in the same block
    ///      which is forbidden to prevent flash loan attacks.
    function test_FailDepositAndWithdrawInSameBlock()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        // skipBlock(1)
        nextCallFails(IVaultManager.CanNotWithdrawInSameBlock.selector)
        withdraw(alice0, contracts.ethVault, 100 ether)
    {}

    modifier mintDyad(uint256 id, uint256 amount) {
        vm.prank(contracts.dNft.ownerOf(id));
        contracts.vaultManager.mintDyad(id, amount, address(this));
        _;
    }

    function test_MintDyad()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, 1e18)
    {
        assertEq(contracts.dyad.balanceOf(address(this)), 1e18);
    }

    function test_CollatRatio() public mintAlice0 {
        /// @dev Before minting DYAD every DNft has the highest possible CR which
        ///      is equal to type(uint).max
        assertTrue(contracts.vaultManager.collatRatio(alice0) == type(uint256).max);
    }

    function test_CollatRatioAfterMinting()
        public
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(1 ether))
    {
        /// @dev Before minting DYAD every DNft has the highest possible CR which
        ///      is equal to type(uint).max. After minting DYAD the CR should be
        ///      less than that.
        assertTrue(contracts.vaultManager.collatRatio(alice0) < type(uint256).max);
    }

    modifier liquidate(uint256 id, uint256 to, address liquidator) {
        deal(address(contracts.dyad), liquidator, _ethToUSD(getMintedDyad(id)));
        vm.prank(liquidator);
        contracts.vaultManager.liquidate(id, to, getMintedDyad(id));
        _;
    }

    function test_Liquidate()
        public
        // alice
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(1 ether))
        changeAsset(alice0, contracts.ethVault, 1.2 ether)
        // bob
        mintBob0
        liquidate(alice0, bob0, bob)
    {
        uint256 ethAfter_Liquidator = contracts.ethVault.id2asset(bob0);
        uint256 ethAfter_Liquidatee = contracts.ethVault.id2asset(alice0);
        uint256 dyadAfter_Liquidatee = contracts.dyad.mintedDyad(alice0);

        assertTrue(ethAfter_Liquidator > 0);
        assertTrue(ethAfter_Liquidatee == 0);

        assertEq(getMintedDyad(alice0), 0);
        assertEq(getCR(alice0), type(uint256).max);
        assertEq(dyadAfter_Liquidatee, 0);
    }

    function testFail_LiquidateNotValidDNftLiquidator()
        public
        // alice
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(1 ether))
        changeAsset(alice0, contracts.ethVault, 1.2 ether)
        liquidate(alice0, RANDOM_NUMBER_0, bob)
    {}

    function testFail_LiquidateNotValidDNftLiquidatee()
        public
        // alice
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        mintDyad(alice0, _ethToUSD(1 ether))
        changeAsset(alice0, contracts.ethVault, 1.2 ether)
        liquidate(RANDOM_NUMBER_0, alice0, alice)
    {}

    function test_LiquidatePartial()
        public
        // alice
        mintAlice0
        addVault(alice0, contracts.ethVault)
        deposit(alice0, contracts.ethVault, 100 ether)
        addVault(alice0, contracts.wstEth)
        deposit(alice0, contracts.wstEth, 100 ether)
        mintDyad(alice0, _ethToUSD(50 ether))
        changeAsset(alice0, contracts.ethVault, 50 ether)
        changeAsset(alice0, contracts.wstEth, 10 ether)
        // bob
        mintBob0
    // liquidate(alice0, bob0, bob)
    {
        uint256 crBefore = getCR(alice0);
        console.log("crBefore: ", crBefore / 1e15);

        uint256 debtBefore = getMintedDyad(alice0);
        console.log("debtBefore: ", debtBefore / 1e18);

        contracts.vaultManager.liquidate(alice0, bob0, _ethToUSD(10 ether));

        uint256 crAfter = getCR(alice0);
        console.log("crAfter: ", crAfter / 1e15);

        uint256 debtAfter = getMintedDyad(alice0);
        console.log("debtAfter: ", debtAfter / 1e18);
    }
}
