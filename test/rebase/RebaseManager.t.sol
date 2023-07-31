pragma solidity 0.8.16;

import {BaseTest} from ".././utils/BaseTest.sol";
import {Dripper} from "../../contracts/rebase/Dripper.sol";
import {RebaseManager} from "../../contracts/rebase/RebaseManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../forge-std/console.sol";
address constant WHALE_USDS = 0x50450351517117Cb58189edBa6bbaD6284D45902;

contract RebaseManagerTest is BaseTest {
    //  Init Variables.
    Dripper public dripper;
    RebaseManager public rebaseManager;

    // Events from the actual contract.
    event DripperChanged(address dripper);
    event GapChanged(uint256 gap);
    event APRChanged(uint256 aprBottom, uint256 aprCap);

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        dripper = new Dripper(VAULT, (86400 * 7));
        dripper.transferOwnership(USDS_OWNER);

        rebaseManager = new RebaseManager(
            VAULT,
            address(dripper),
            86400 * 7, // set Minimum Gap time
            1000,
            800
        );
        rebaseManager.transferOwnership(USDS_OWNER);
    }
}

contract SetDripper is RebaseManagerTest {
    function test_revertsWhen_vaultIsZeroAddress()
        external
        useKnownActor(USDS_OWNER)
    {
        address newVaultAddress = address(0);
        vm.expectRevert("Invalid Address");
        rebaseManager.setDripper(newVaultAddress);
    }

    function test_revertsWhen_callerIsNotOwner() external useActor(0) {
        address newVaultAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.setDripper(newVaultAddress);
    }

    function test_setDripper() external useKnownActor(USDS_OWNER) {
        address newVaultAddress = address(1);
        vm.expectEmit(true, true, false, true);
        emit DripperChanged(address(1));
        rebaseManager.setDripper(newVaultAddress);
    }
}

contract SetGap is RebaseManagerTest {
    function test_SetGap_Zero() external useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, false, true);
        emit GapChanged(0);
        rebaseManager.setGap(0);
    }

    function test_revertsWhen_callerIsNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.setGap(86400 * 7);
    }

    function test_setGap(uint256 gap) external useKnownActor(USDS_OWNER) {
        vm.assume(gap != 0);

        vm.expectEmit(true, true, false, true);
        emit GapChanged(gap);
        rebaseManager.setGap(gap);
    }
}

contract SetAPR is RebaseManagerTest {
    function test_revertsWhen_invalidConfig(
        uint256 aprBottom,
        uint256 aprCap
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(aprBottom > aprCap);
        vm.expectRevert("Invalid APR config");
        rebaseManager.setAPR(aprBottom, aprCap);
    }

    function test_revertsWhen_callerIsNotOwner(
        uint256 aprBottom,
        uint256 aprCap
    ) external useActor(0) {
        vm.assume(aprBottom <= aprCap);
        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.setAPR(aprBottom, aprCap);
    }

    function test_setAPR(
        uint256 aprBottom,
        uint256 aprCap
    ) external useKnownActor(USDS_OWNER) {
        vm.assume(aprBottom <= aprCap);
        vm.expectEmit(true, true, false, true);
        emit APRChanged(aprBottom, aprCap);
        rebaseManager.setAPR(aprBottom, aprCap);
    }
}

contract FetchRebaseAmt is RebaseManagerTest {
    function test_revertsWhen_callerIsNotOwner_rebase() external useActor(0) {
        vm.expectRevert("Unauthorized caller");
        rebaseManager.fetchRebaseAmt();
    }

    function test_fetchRebaseAmt_zeroAmt() external useKnownActor(VAULT) {
        rebaseManager.fetchRebaseAmt();
        skip(86400 * 10);
        vm.startPrank(WHALE_USDS);
        IERC20(USDS).approve(WHALE_USDS, 100000 * 10 ** 18);
        IERC20(USDS).transfer(address(dripper), 10000 * 10 ** 18);
        vm.stopPrank();

        (uint256 min, uint256 max) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("1", min / (10 ** 18), "max", max / (10 ** 18));
        uint256 collectable0 = dripper.getCollectableAmt();
        console.log("collectable0", collectable0 / 10 ** 18);

        vm.startPrank(VAULT);
        skip(86400 * 10);

        rebaseManager.fetchRebaseAmt();
        (uint256 min2, uint256 max2) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("2", min2 / (10 ** 18), "max", max2 / (10 ** 18));
        dripper.collect();
        uint256 collectable = dripper.getCollectableAmt();
        console.log("collectable", collectable / 10 ** 18);
        skip(86400 * 10);
        uint256 rebaseAmt = rebaseManager.getAvailableRebaseAmt();
        console.log("Rebase Amount", rebaseAmt / 10 ** 18);
        rebaseManager.fetchRebaseAmt();
        (uint256 min3, uint256 max3) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("3", min3 / (10 ** 18), "max", max3 / (10 ** 18));
    }
}
