// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Parameters} from "../../src/params/Parameters.sol";
import {Licenser} from "../../src/core/Licenser.sol";
import {Modifiers} from "../Modifiers.sol";
import {DeployV2, Contracts} from "../../script/deploy/Deploy.V2.s.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";

contract BaseTestV2 is Modifiers, Parameters {
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    Contracts contracts;
    ERC20 weth;

    uint256 ETH_TO_USD; // 1e8
    uint256 MIN_COLLAT_RATIO;

    uint256 RANDOM_NUMBER_0 = 471966444;

    uint256 alice0;
    uint256 alice1;
    uint256 bob0;
    uint256 bob1;

    address alice;
    address bob = address(0x42);

    function setUp() public {
        contracts = new DeployV2().run();
        weth = ERC20(MAINNET_WETH);
        alice = address(this);

        ETH_TO_USD = contracts.ethVault.assetPrice();
        MIN_COLLAT_RATIO = contracts.vaultManager.MIN_COLLAT_RATIO();

        licenseVauleManager();
    }

    // --- alice ---
    modifier mintAlice0() {
        alice0 = mintDNft(address(this));
        _;
    }

    modifier mintAlice1() {
        alice1 = mintDNft(address(this));
        _;
    }
    // --- bob ---

    modifier mintBob0() {
        bob0 = mintDNft(bob);
        _;
    }

    modifier mintBob1() {
        bob1 = mintDNft(bob);
        _;
    }

    function mintDNft(address owner) public returns (uint256 id) {
        uint256 startPrice = contracts.dNft.START_PRICE();
        uint256 priceIncrease = contracts.dNft.PRICE_INCREASE();
        uint256 publicMints = contracts.dNft.publicMints();
        uint256 price = startPrice + (priceIncrease * publicMints);
        vm.deal(address(this), price);
        id = contracts.dNft.mintNft{value: price}(owner);
    }

    function licenseVauleManager() public {
        Licenser licenser = Licenser(MAINNET_VAULT_MANAGER_LICENSER);
        vm.prank(MAINNET_OWNER);
        licenser.add(address(contracts.vaultManager));
    }

    // -- helpers --
    function _ethToUSD(uint256 eth) public view returns (uint256) {
        return eth * ETH_TO_USD / 1e8;
    }

    function getMintedDyad(uint256 id) public view returns (uint256) {
        return contracts.dyad.mintedDyad(id);
    }

    function getCR(uint256 id) public view returns (uint256) {
        return contracts.vaultManager.collatRatio(id);
    }

    // -- storage manipulation --
    function _changeAsset(uint256 id, IVault vault, uint256 amount) public {
        stdstore.target(address(vault)).sig("id2asset(uint256)").with_key(id).checked_write(amount);
    }

    // Manually set the Collaterization Ratio of a dNft by changing the the asset
    // of the vault.
    function changeCollatRatio(uint256 id, IVault vault, uint256 newCr) public {
        uint256 debt = getMintedDyad(id);
        uint256 value = newCr.mulWadDown(debt);
        uint256 asset =
            value * (10 ** (vault.oracle().decimals() + vault.asset().decimals())) / vault.assetPrice() / 1e18;

        _changeAsset(id, vault, asset);
    }

    // --- modifiers ---
    modifier changeAsset(uint256 id, IVault vault, uint256 amount) {
        _changeAsset(id, vault, amount);
        _;
    }

    modifier deposit(uint256 id, IVault vault, uint256 amount) {
        address owner = contracts.dNft.ownerOf(id);
        vm.startPrank(owner);

        ERC20 asset = vault.asset();
        deal(address(asset), owner, amount);
        asset.approve(address(contracts.vaultManager), amount);
        contracts.vaultManager.deposit(id, address(vault), amount);

        vm.stopPrank();
        _;
    }

    modifier addVault(uint256 id, IVault vault) {
        vm.prank(contracts.dNft.ownerOf(id));
        contracts.vaultManager.add(id, address(vault));
        _;
    }

    // --- RECEIVER ---
    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }
}
