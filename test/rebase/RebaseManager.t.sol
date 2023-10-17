pragma solidity 0.8.16;

import {PreMigrationSetup} from ".././utils/DeploymentSetup.sol";
import {Dripper} from "../../contracts/rebase/Dripper.sol";
import {RebaseManager, Helpers} from "../../contracts/rebase/RebaseManager.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";

contract RebaseManagerTest is PreMigrationSetup {
    //  Init Variables.
    Dripper public dripper;
    RebaseManager public rebaseManager;
    IVault internal vault;
    uint256 USDCePrecision;
    uint256 USDsPrecision;

    // Events from the actual contract.
    event VaultUpdated(address vault);
    event DripperUpdated(address dripper);
    event GapUpdated(uint256 gap);
    event APRUpdated(uint256 aprBottom, uint256 aprCap);

    error CallerNotVault(address caller);
    error InvalidAPRConfig(uint256 aprBottom, uint256 aprCap);

    function setUp() public override {
        super.setUp();
        USDCePrecision = 10 ** ERC20(USDCe).decimals();
        USDsPrecision = 10 ** ERC20(USDS).decimals();
        vm.startPrank(USDS_OWNER);
        dripper = Dripper(DRIPPER);
        rebaseManager = RebaseManager(REBASE_MANAGER);
        vm.stopPrank();
    }

    function mintUSDs(uint256 amountIn) public {
        vm.startPrank(USDS_OWNER);

        deal(address(USDCe), USDS_OWNER, amountIn);

        IERC20(USDCe).approve(VAULT, amountIn);
        IVault(VAULT).mintBySpecifyingCollateralAmt(USDCe, amountIn, 0, 0, block.timestamp + 1200);
        vm.stopPrank();
    }
}

contract UpdateVault is RebaseManagerTest {
    function test_RevertWhen_VaultIsZeroAddress() external useKnownActor(USDS_OWNER) {
        address newVaultAddress = address(0);
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        rebaseManager.updateVault(newVaultAddress);
    }

    // Can't set the fuzzer for address type
    function test_UpdateVault() external useKnownActor(USDS_OWNER) {
        address newVaultAddress = address(1);
        vm.expectEmit(true, true, false, true);
        emit VaultUpdated(address(1));

        rebaseManager.updateVault(newVaultAddress);
    }

    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        address newVaultAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateVault(newVaultAddress);
    }
}

contract UpdateDripper is RebaseManagerTest {
    function test_RevertWhen_DripperIsZeroAddress() external useKnownActor(USDS_OWNER) {
        address newDripperAddress = address(0);
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        rebaseManager.updateDripper(newDripperAddress);
    }

    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        address newDripperAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateDripper(newDripperAddress);
    }

    function test_UpdateDripper() external useKnownActor(USDS_OWNER) {
        address newDripperAddress = address(1);
        vm.expectEmit(true, true, false, true);
        emit DripperUpdated(address(1));
        rebaseManager.updateDripper(newDripperAddress);
    }
}

contract UpdateGap is RebaseManagerTest {
    function test_UpdateGap_Zero() external useKnownActor(USDS_OWNER) {
        vm.expectEmit(true, true, false, true);
        emit GapUpdated(0);
        rebaseManager.updateGap(0);
    }

    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateGap(86400 * 7);
    }

    function test_UpdateGap(uint256 gap) external useKnownActor(USDS_OWNER) {
        vm.assume(gap != 0);

        vm.expectEmit(true, true, false, true);
        emit GapUpdated(gap);
        rebaseManager.updateGap(gap);
    }
}

contract UpdateAPR is RebaseManagerTest {
    function test_RevertWhen_InvalidConfig(uint256 aprBottom, uint256 aprCap) external useKnownActor(USDS_OWNER) {
        vm.assume(aprBottom > aprCap);
        vm.expectRevert(abi.encodeWithSelector(InvalidAPRConfig.selector, aprBottom, aprCap));
        rebaseManager.updateAPR(aprBottom, aprCap);
    }

    function test_RevertWhen_CallerIsNotOwner(uint256 aprBottom, uint256 aprCap) external useActor(0) {
        vm.assume(aprBottom <= aprCap);
        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateAPR(aprBottom, aprCap);
    }

    function test_UpdateAPR(uint256 aprBottom, uint256 aprCap) external useKnownActor(USDS_OWNER) {
        vm.assume(aprBottom <= aprCap);
        vm.expectEmit(true, true, false, true);
        emit APRUpdated(aprBottom, aprCap);
        rebaseManager.updateAPR(aprBottom, aprCap);
    }
}

contract FetchRebaseAmt is RebaseManagerTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CallerNotVault.selector, actors[0]));
        rebaseManager.fetchRebaseAmt();
    }

    function test_FetchRebaseAmt_Scenario() external {
        vm.prank(VAULT);
        rebaseManager.fetchRebaseAmt();
        skip(86400 * 10);
        // Minting USDs
        mintUSDs(1e11);
        vm.prank(USDS_OWNER);
        IERC20(USDS).transfer(address(dripper), 1e22);

        vm.startPrank(VAULT);
        dripper.collect();
        console.log("Day 1 After Minting USDs");
        skip(86400 * 1);
        (uint256 min, uint256 max) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("Min Rebase Amt", min / (10 ** 18), "max Rebase Amt", max / (10 ** 18));
        uint256 collectable0 = dripper.getCollectableAmt();
        console.log("collectable0", collectable0 / 10 ** 18);
        skip(86400 * 1);
        console.log("Day 2 After Minting USDs");
        (uint256 min2, uint256 max2) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("Min Rebase Amt", min2 / (10 ** 18), "max Rebase Amt", max2 / (10 ** 18));
        uint256 collectable = dripper.getCollectableAmt();
        console.log("collectable1", collectable / 10 ** 18);
        uint256 rebaseAmt1 = rebaseManager.fetchRebaseAmt();
        console.log("Rebase Amount", rebaseAmt1 / 10 ** 18);
        // Trying to collect from dripper after rebase
        dripper.collect();
        skip(86400 * 1);
        console.log("Day 3 After Minting USDs");
        (uint256 min3, uint256 max3) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("Min Rebase Amt", min3 / (10 ** 18), "max Rebase Amt", max3 / (10 ** 18));
        uint256 collectable3 = dripper.getCollectableAmt();
        console.log("collectable3", collectable3 / 10 ** 18);
        uint256 rebaseAmt3 = rebaseManager.fetchRebaseAmt();
        console.log("Rebase Amount", rebaseAmt3 / 10 ** 18);
    }
}
