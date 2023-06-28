pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AaveStrategy} from "../contracts/strategies/aave/AaveStrategy.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import  "forge-std/console.sol";
import "forge-std/StdCheats.sol";

abstract contract BaseTest is Test {
    // Define global constants | Test config
    // @dev Make it 0 to test on latest
    uint256 public constant FORK_BLOCK = 96_705_562;
    uint256 public constant NUM_ACTORS = 5;

    // Define common constants here
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDS_OWNER = 0x5b12d9846F8612E439730d18E1C12634753B1bF1;
    address public constant PROXY_ADMIN = 0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25;

    
    // Define fork networks
    uint256 arbFork;

    address[] public actors;
    address internal currentActor;
    
    /// @notice Get a pre-set address for prank
    /// @param actorIndex Index of the actor
    modifier useActor(uint256 actorIndex) {
        currentActor = actors[bound(actorIndex, 0, actors.length -1)];
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
    function setUp() virtual public {
        
        /// @dev Initialize actors for testing. 
        for(uint256 i = 0; i < NUM_ACTORS; ++i) {
            actors.push(makeAddr(Strings.toString(i)));
        }
    }

    /// @notice 
    function setArbitrumFork() public {
        string memory ARBITRUM_RPC_URL = vm.envString("ARB_URL");
        arbFork = vm.createFork(ARBITRUM_RPC_URL);        
        vm.selectFork(arbFork);
        if (FORK_BLOCK != 0) vm.rollFork(FORK_BLOCK);
    }
}