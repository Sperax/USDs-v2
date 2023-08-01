pragma solidity 0.8.16;

import {BaseTest} from ".././utils/BaseTest.sol";
import {Dripper} from "../../contracts/rebase/Dripper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

address constant WHALE_USDS = 0x50450351517117Cb58189edBa6bbaD6284D45902;

interface IUSDS {
    function approve(address _spender, uint256 _value) external returns (bool);

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool);
}

contract DripperTest is BaseTest {
    //  Init Variables.
    Dripper public dripper;

    // Events from the actual contract.
    event Collected(uint256 amount);
    event VaultChanged(address vault);
    event DripDurationChanged(uint256 dripDuration);
    event Recovered(address owner, uint256 amount);

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        dripper = new Dripper(VAULT, (86400 * 7));
        dripper.transferOwnership(USDS_OWNER);
    }
}

contract SetVault is DripperTest {
    function test_revertsWhen_vaultIsZeroAddress()
        external
        useKnownActor(USDS_OWNER)
    {
        address newVaultAddress = address(0);
        vm.expectRevert("Zero address");
        dripper.setVault(newVaultAddress);
    }

    // Can't set the fuzzer for address type
    function test_setVault() external useKnownActor(USDS_OWNER) {
        address newVaultAddress = address(1);
        vm.expectEmit(true, true, false, true);
        emit VaultChanged(address(1));

        dripper.setVault(newVaultAddress);
    }

    function test_revertsWhen_callerIsNotOwner() external useActor(0) {
        address newVaultAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        dripper.setVault(newVaultAddress);
    }
}

contract SetDripDuration is DripperTest {
    function test_revertsWhen_invalidInput(
        uint256 dripDuration
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(dripDuration == 0);
        vm.expectRevert("Invalid input");
        dripper.setDripDuration(dripDuration);
    }

    // Can't set the fuzzer for address type
    function test_setDripDuration(
        uint256 dripDuration
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(dripDuration != 0);
        vm.expectEmit(true, true, false, true);
        emit DripDurationChanged(dripDuration);

        dripper.setDripDuration(dripDuration);
    }

    function test_revertsWhen_callerIsNotOwner(
        uint256 dripDuration
    ) external useActor(0) {
        vm.assume(dripDuration != 0);

        vm.expectRevert("Ownable: caller is not the owner");
        dripper.setDripDuration(dripDuration);
    }
}

contract RecoverTokens is DripperTest {
    function test_revertsWhen_callerIsNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        dripper.recoverTokens(USDCe);
    }

    function test_revertsWhen_nothingToRecover()
        external
        useKnownActor(USDS_OWNER)
    {
        vm.expectRevert("Nothing to recover");
        dripper.recoverTokens(USDCe);
    }

    function test_recoverTokens(
        uint128 amount
    ) external useKnownActor(USDS_OWNER) {
        address[5] memory assets = [USDCe, USDT, VST, FRAX, DAI];
        vm.assume(amount != 0);
        for (uint8 i = 0; i < assets.length; i++) {
            deal(address(assets[i]), address(dripper), amount, true);
            vm.expectEmit(true, true, false, true);
            emit Recovered(USDS_OWNER, amount);
            dripper.recoverTokens((assets[i]));
        }
    }
}

contract Collect is DripperTest {
    function test_collect_zero_balance() external useActor(0) {
        assertEq(dripper.getCollectableAmt(), 0);
        dripper.collect();
    }

    function test_collectDripper() external useKnownActor(WHALE_USDS) {
        IERC20(USDS).approve(WHALE_USDS, 100000 * 10 ** 18);
        IERC20(USDS).transfer(address(dripper), 10000 * 10 ** 18);
        // deal(USDS, address(dripper), 1, true);
        skip(86400);
        dripper.collect();
        skip(86400 * 14);
        vm.expectEmit(true, true, false, true);
        emit Collected(10000 * 10 ** 18);
        dripper.collect();
    }
}
