# Testing guidelines with foundry
### Note: Below guidelines are taken from [official foundry docs](https://book.getfoundry.sh/tutorials/best-practices) and modified as per our needs

## General Test Guidance
1. For testing MyContract.sol, the test file should be MyContract.t.sol. For testing MyScript.s.sol, the test file should be MyScript.t.sol.

    * If the contract is big and you want to split it over multiple files, group them logically like MyContract.owner.t.sol, MyContract.deposits.t.sol, etc.

2. Never make assertions in the setUp function, instead use a dedicated test like test_SetUpState() if you need to ensure your setUp function does what you expected. More info on why in foundry-rs/foundry#1291

3. For unit tests, treat contracts as describe blocks:
    * `contract Add` holds all unit tests for the add method of MyContract.
    * `contract Supply` holds all tests for the supply method.
    * `contract Constructor` hold all tests for the constructor.
    * A benefit of this approach is that smaller contracts should compile faster than large ones, so this approach of many small contracts should save time as test suites get large.

4. Some general guidance for all tests:

    * Test contracts/functions should be written in the same order as the original functions in the contract-under-test.
    * All unit tests that test the same function should live serially in the test file.
    * Test contracts can inherit from any helper contracts you want. For example contract MyContractTest tests MyContract, but may inherit from forge-std's Test, as well as e.g. your own TestUtilities helper contract.

5. Integration tests should live in the same test directory, with a clear naming convention. These may be in dedicated files, or they may live next to related unit tests in existing test files.

6. Be consistent with test naming, as it's helpful for filtering tests (e.g. for gas reports you might want to filter out revert tests). When combining naming conventions, keep them alphabetical. Below is a sample of valid names. A comprehensive list of valid and invalid examples can be found [here](https://github.com/ScopeLift/scopelint/blob/1857e3940bfe92ac5a136827374f4b27ff083971/src/check/validators/test_names.rs#L106-L143).
    * `test_Description` for standard tests.
    * `testFuzz_Description` for fuzz tests.
    * `test_Revert[If|When]_Condition` for tests expecting a revert.
    * `testFork_Description` for tests that fork from a network.
    * `testForkFuzz_Revert[If|When]_Condition` for a fuzz test that forks and expects a revert.

7. Name your constants and immutables using `ALL_CAPS_WITH_UNDERSCORES`, to make it easier to distinguish them from variables and functions.

8. When testing events, prefer setting all expectEmit arguments to true, i.e. vm.expectEmit(true, true, true, true) or vm.expectEmit(). Benefits:
    * This ensures you test everything in your event.
    * If you add a topic (i.e. a new indexed parameter), it's now tested by default.
    * Even if you only have 1 topic, the extra true arguments don't hurt.

9. When using assertions like assertEq, consider leveraging the last string param to make it easier to identify failures. These can be kept brief, or even just be numbers—they basically serve as a replacement for showing line numbers of the revert, e.g. assertEq(x, y, "1") or assertEq(x, y, "sum1").

10. Remember to write invariant tests! For the assertion string, use a verbose english description of the invariant: assertEq(x + y, z, "Invariant violated: the sum of x and y must always equal z"). For more info on this, check out the Invariant Testing tutorial.

## Test Harness

### Internal Functions
To test internal functions, write a harness contract that inherits from the contract under test (CuT). Harness contracts that inherit from the CuT expose the internal functions as external ones.

Each internal function that is tested should be exposed via an external one with a name that follows the pattern exposed_<function_name>. For example:


```js
// file: src/MyContract.sol
contract MyContract {
  function myInternalMethod() internal returns (uint) {
    return 42;
  }
}

// file: test/MyContract.t.sol
import {MyContract} from "src/MyContract.sol";

contract MyContractHarness is MyContract {
  // Deploy this contract then call this method to test `myInternalMethod`.
  function exposed_myInternalMethod() external returns (uint) {
    return myInternalMethod();
  }
}
```

### Private Functions
Unfortunately there is currently no good way to unit test private methods since they cannot be accessed by any other contracts. Options include:
* Converting private functions to internal.
* Copy/pasting the logic into your test contract and writing a script that runs in CI check to ensure both functions are identical.

## Test Setup
* Foundry test scripts are written to run on `Arbitrum-fork-network`.
* Update the `.env` file with required parameters from `.env.example`
* Use below commands to run the test scripts and coverage.
  ``` bash
    $ forge test
    $ forge coverage
    $ npm run forge-coverage # Gets the code coverage for contracts excluding test files
  ```
