pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract Setup is Test {
    // Define global constants | Test config
    // @dev Make it 0 to test on latest
    uint256 public constant FORK_BLOCK = 96_705_562;
    uint256 public constant NUM_ACTORS = 5;

    // Define Collateral constants here
    address public constant USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address public constant VST = 0x64343594Ab9b56e99087BfA6F2335Db24c2d1F17;
    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    // Define common constants here
    address internal USDS;
    address internal SPA;
    address internal USDS_OWNER;
    address internal SPA_BUYBACK;
    address internal PROXY_ADMIN;
    address internal VAULT;
    address internal FEE_CALCULATOR;
    address internal COLLATERAL_MANAGER;
    address internal MASTER_PRICE_ORACLE;
    address internal YIELD_RESERVE;
    address internal ORACLE;
    address internal DRIPPER;
    address internal REBASE_MANAGER;
    address internal BUYBACK;

    // Define fork networks
    uint256 internal arbFork;

    address[] public actors;
    address internal currentActor;

    /// @notice Get a pre-set address for prank
    /// @param actorIndex Index of the actor
    modifier useActor(uint256 actorIndex) {
        currentActor = actors[bound(actorIndex, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Start a prank session with a known user addr
    modifier useKnownActor(address user) {
        currentActor = user;
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Initialize global test configuration.
    function setUp() public virtual {
        /// @dev Initialize actors for testing.
        for (uint256 i = 0; i < NUM_ACTORS; ++i) {
            actors.push(makeAddr(Strings.toString(i)));
        }
    }

    /// @notice
    function setArbitrumFork() public {
        string memory arbRpcUrl = vm.envString("ARB_URL");
        arbFork = vm.createFork(arbRpcUrl);
        vm.selectFork(arbFork);
        if (FORK_BLOCK != 0) vm.rollFork(FORK_BLOCK);
    }
}

abstract contract BaseTest is Setup {
    function setUp() public virtual override {
        super.setUp();

        USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
        SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
        USDS_OWNER = 0x5b12d9846F8612E439730d18E1C12634753B1bF1;
        PROXY_ADMIN = 0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25;
        DRIPPER = 0xf3f98086f7B61a32be4EdF8d8A4b964eC886BBcd; // dummy addr
        REBASE_MANAGER = 0xf3f98086f7B61a32be4EdF8d8A4b964eC886BBcd; // dummy addr
        SPA_BUYBACK = 0xFbc0d3cA777722d234FE01dba94DeDeDb277AFe3;
        BUYBACK = 0xf3f98086f7B61a32be4EdF8d8A4b964eC886BBcd;
        VAULT = 0xF783DD830A4650D2A8594423F123250652340E3f;
        ORACLE = 0xf3f98086f7B61a32be4EdF8d8A4b964eC886BBcd;
    }
}
