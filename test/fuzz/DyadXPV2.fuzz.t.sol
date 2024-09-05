import {Test} from "forge-std/Test.sol";
import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {DyadXPv2} from "../../src/staking/DyadXPv2.sol";
import {Kerosine} from "../../src/staking/Kerosine.sol";
import {DNft} from "../../src/core/DNft.sol";
import {KeroseneVault} from "../../src/core/VaultKerosene.sol";
import {Dyad} from "../../src/core/Dyad.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {KerosineManager} from "../../src/core/KerosineManager.sol";
import {Licenser} from "../../src/core/Licenser.sol";
import {KerosineDenominator} from "../../src/staking/KerosineDenominator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DyadXPFuzzTest is Test {
    address VAULT_MANAGER = address(0x5678);

    DyadXPv2 momentum;
    Kerosine kerosine;
    DNft dnft;
    Dyad dyad;
    KeroseneVault keroseneVault;

    address USER_1 = address(0x1111);
    address USER_2 = address(0x2222);
    address USER_3 = address(0x3333);

    function setUp() external {
        Licenser licenser = new Licenser();
        dyad = new Dyad(licenser);
        dnft = new DNft();
        kerosine = new Kerosine();
        keroseneVault = new KeroseneVault(
            IVaultManager(VAULT_MANAGER),
            kerosine,
            dyad,
            KerosineManager(address(0x0)),
            IAggregatorV3(address(0x0)),
            KerosineDenominator(address(0x0))
        );
        DyadXPv2 impl = new DyadXPv2(
            VAULT_MANAGER,
            address(keroseneVault),
            address(dnft),
            address(dyad)
        );
        momentum = DyadXPv2(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSignature("initialize()")
                )
            )
        );

        dnft.mintInsiderNft(USER_1);
        dnft.mintInsiderNft(USER_2);
        dnft.mintInsiderNft(USER_3);

        licenser.add(VAULT_MANAGER);
    }

    function testFuzz_totalSupplyGteAllBalances(
        uint256 deposit1,
        uint256 deposit2,
        uint256 deposit3
    ) external {
        vm.assume(deposit1 > 1);
        vm.assume(deposit2 > 1);
        vm.assume(deposit3 > 1);
        vm.assume(deposit1 < kerosine.totalSupply());
        vm.assume(deposit2 < kerosine.totalSupply());
        vm.assume(deposit3 < kerosine.totalSupply());
        vm.assume(deposit1 + deposit2 + deposit3 <= kerosine.totalSupply());

        momentum.setHalvingConfiguration(uint40(block.timestamp), 1 minutes);

        kerosine.transfer(address(keroseneVault), deposit1);
        vm.startPrank(VAULT_MANAGER);
        keroseneVault.deposit(0, deposit1);
        momentum.afterKeroseneDeposited(0, deposit1);
        vm.stopPrank();

        kerosine.transfer(address(keroseneVault), deposit2);
        vm.startPrank(VAULT_MANAGER);
        dyad.mint(1, address(this), 10_000 * 1e18);
        momentum.afterDyadMinted(1);
        keroseneVault.deposit(1, deposit2);
        momentum.afterKeroseneDeposited(1, deposit2);
        vm.stopPrank();

        kerosine.transfer(address(keroseneVault), deposit3);
        vm.startPrank(VAULT_MANAGER);
        keroseneVault.deposit(2, deposit3);
        momentum.afterKeroseneDeposited(2, deposit3);
        vm.stopPrank();

        _checkInvariantSupplyBalances();

        vm.warp(block.timestamp + 1 minutes);
        _checkInvariantSupplyBalances();

        vm.warp(block.timestamp + 1 hours);
        _checkInvariantSupplyBalances();

        vm.warp(block.timestamp + 1 days);
        _checkInvariantSupplyBalances();

        vm.startPrank(VAULT_MANAGER);
        uint256 totalMomentumBefore = momentum.totalSupply();
        uint256 userMomentumBefore = momentum.balanceOf(USER_1);
        momentum.beforeKeroseneWithdrawn(0, deposit1 / 2);
        keroseneVault.withdraw(0, USER_1, deposit1 / 2);
        uint256 totalMomentumAfter = momentum.totalSupply();
        uint256 userMomentumAfter = momentum.balanceOf(USER_1);
        assertTrue(totalMomentumBefore > totalMomentumAfter);
        assertTrue(userMomentumBefore > userMomentumAfter);
        keroseneVault.deposit(0, deposit1 / 2);
        momentum.afterKeroseneDeposited(0, deposit1 / 2);
        assertEq(momentum.totalSupply(), totalMomentumAfter);
        assertEq(momentum.balanceOf(USER_1), userMomentumAfter);
        vm.stopPrank();

        _checkInvariantSupplyBalances();
    }

    function _checkInvariantSupplyBalances() internal view {
        uint256 totalSupply = momentum.totalSupply();
        uint256 balance1 = momentum.balanceOf(USER_1);
        uint256 balance2 = momentum.balanceOf(USER_2);
        uint256 balance3 = momentum.balanceOf(USER_3);

        vm.assertGe(totalSupply, balance1 + balance2 + balance3);
    }
}
