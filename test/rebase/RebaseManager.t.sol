pragma solidity 0.8.16;

import {PreMigrationSetup} from ".././utils/DeploymentSetup.sol";
import {Dripper} from "../../contracts/rebase/Dripper.sol";
import {RebaseManager} from "../../contracts/rebase/RebaseManager.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
address constant WHALE_USDS = 0x50450351517117Cb58189edBa6bbaD6284D45902;

contract RebaseManagerTest is PreMigrationSetup {
    //  Init Variables.
    Dripper public dripper;
    RebaseManager public rebaseManager;
    IVault internal vault;
    uint256 USDCePrecision;
    uint256 USDsPrecision;

    // Events from the actual contract.
    event DripperChanged(address dripper);
    event GapChanged(uint256 gap);
    event APRChanged(uint256 aprBottom, uint256 aprCap);

    function setUp() public override {
        super.setUp();
        USDCePrecision = 10 ** ERC20(USDCe).decimals();
        USDsPrecision = 10 ** ERC20(USDS).decimals();
        vm.startPrank(USDS_OWNER);
        dripper = Dripper(DRIPPER);
        rebaseManager = RebaseManager(REBASE_MANAGER);
        vm.stopPrank();
    }

    function mockPrice(address token, uint256 price, uint256 precision) public {
        vm.mockCall(
            ORACLE,
            abi.encodeWithSignature("getPrice(address)", token),
            abi.encode([price, precision])
        );
    }

    function mintUSDs(uint256 amountIn) public {
        mockPrice(USDCe, 1e8, 1e8);
        mockPrice(USDS, 1e18, 1e18);

        vm.startPrank(USDS_OWNER);

        deal(address(USDCe), USDS_OWNER, amountIn);

        IERC20(USDCe).approve(VAULT, amountIn);
        IVault(VAULT).mintBySpecifyingCollateralAmt(
            USDCe,
            amountIn,
            0,
            0,
            block.timestamp + 1200
        );
        vm.stopPrank();
    }
}

contract SetDripper is RebaseManagerTest {
    function test_revertsWhen_dripperIsZeroAddress()
        external
        useKnownActor(USDS_OWNER)
    {
        address newDripperAddress = address(0);
        vm.expectRevert("Invalid Address");
        rebaseManager.setDripper(newDripperAddress);
    }

    function test_revertsWhen_callerIsNotOwner() external useActor(0) {
        address newVaultAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.setDripper(newVaultAddress);
    }

    function test_setDripper() external useKnownActor(USDS_OWNER) {
        address newDripperAddress = address(1);
        vm.expectEmit(true, true, false, true);
        emit DripperChanged(address(1));
        rebaseManager.setDripper(newDripperAddress);
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

    function test_fetchRebaseAmt_zeroAmt() external {
        vm.prank(VAULT);
        rebaseManager.fetchRebaseAmt();
        skip(86400 * 10);
        // Minting USDs
        mintUSDs(1e11);
        vm.prank(USDS_OWNER);
        IERC20(USDS).transfer(address(dripper), 1e22);

        vm.startPrank(VAULT);
        //Transferring USDs from Whale
        // vm.startPrank(WHALE_USDS);
        // IERC20(USDS).approve(WHALE_USDS, 100000 * 10 ** 18);
        // IERC20(USDS).transfer(address(dripper), 10000 * 10 ** 18);
        dripper.collect();

        skip(86400 * 1);
        (uint256 min, uint256 max) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("1", min / (10 ** 18), "max", max / (10 ** 18));
        uint256 collectable0 = dripper.getCollectableAmt();
        console.log("collectable0", collectable0 / 10 ** 18);
        skip(86400 * 10);

        (uint256 min2, uint256 max2) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("2", min2 / (10 ** 18), "max", max2 / (10 ** 18));
        uint256 collectable = dripper.getCollectableAmt();
        console.log("collectable1", collectable / 10 ** 18);
        uint256 rebaseAmt1 = rebaseManager.fetchRebaseAmt();
        console.log("Rebase Amount", rebaseAmt1 / 10 ** 18);

        skip(86400 * 10);
        uint256 collectable2 = dripper.getCollectableAmt();
        console.log("collectable2", collectable2 / 10 ** 18);

        uint256 rebaseAmt = rebaseManager.getAvailableRebaseAmt();
        console.log("Rebase Amount", rebaseAmt / 10 ** 18);
        rebaseManager.fetchRebaseAmt();
        (uint256 min3, uint256 max3) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("3", min3 / (10 ** 18), "max", max3 / (10 ** 18));
    }
}
