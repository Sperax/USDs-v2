# Contribution Guidelines

Thank you for considering contributing to the USDs Protocol! Your involvement is highly appreciated. This guide outlines how you can participate and contribute effectively. Before you start, please familiarize yourself with these guidelines to ensure a smooth collaboration.

## Table of Contents

- [Getting Started](#getting-started)
- [Code of Conduct](#code-of-conduct)
- [Types of Contributions](#types-of-contributions)
- [Opening an Issue](#opening-an-issue)
- [Opening a Pull Request](#opening-a-pull-request)
- [Standards](#standards)
- [Community](#community)
- [License](#license)

## Getting Started

Before you contribute, make sure you have:

- A GitHub account. If you don't have one, you can [sign up here](https://github.com/join).
- Familiarity with USDs Protocol. Learn more on our [website](https://app.sperax.io/) or explore our [documentation](https://docs.sperax.io/).
- Foundry installed. Follow the steps [here](https://book.getfoundry.sh/getting-started/installation) to install Foundry.

## Code of Conduct

As contributors, we commit to respecting everyone participating in this project. Project maintainers reserve the right to remove content that violates the Code of Conduct. Please review our Code of Conduct for more details.

## Types of Contributions

Various ways to contribute include:

1. **Opening an issue:** Check for [existing issues](https://github.com/Sperax/USDs-v2/issues) before opening a new one. Provide details within an open issue rather than duplicating it. We welcome feedback and suggestions on the development process.

2. **Resolving an issue:** Address an issue by either disproving it or fixing it with code changes. Any pull request fixing an issue should reference that issue.

3. **Reviewing open PRs:** Provide comments, guidance on standards, naming suggestions, gas optimizations, or alternative design ideas on any open pull request.

To contact maintainers or seek clarification, message in the `#engineering-dev` room on our official [Discord](https://discord.com/invite/cFdcvj9jMm).

## Opening an Issue

When [opening an issue](https://github.com/Sperax/USDs-v2/issues/new/choose), choose a template: Bug Report or Feature Improvement. For bug reports, demonstrate the bug through tests or proof of concept implementations. For feature improvements, title it concisely and ensure a similar request is not already open or in progress. Follow up on any questions or comments from others regarding the issue.

Feel free to tag the issue as a “good first issue” for cleanup-related tasks or small-scoped changes to encourage pull requests from first-time contributors!

## Opening a Pull Request

Open all pull requests against the `main` branch. Reference the issue you are addressing in the pull request.

Community members can review pull requests, but maintainers' approval is needed for merging. Understand it may take time for a response, but maintainers will aim to comment as soon as possible.

**For significant code changes, open an issue to discuss changes with maintainers before development.**

Before opening a pull request:

- Ensure code style follows the [standards](#standards).
- Run tests and check coverage.
- Add extensive code documentation following Solidity [standards](https://docs.soliditylang.org/en/latest/natspec-format.html).
- Include tests. For smaller contributions, use unit tests and fuzz tests. For larger contributions, include integration tests and invariant tests where possible.

## Standards

All contributions must adhere to the following standards. PRs not following these standards will be closed by maintainers.

1. Format contracts with the default Forge `fmt` config. Run `forge fmt`.
2. Follow the [Solidity style guide](https://docs.soliditylang.org/en/v0.8.17/style-guide.html) with the exception of using the _prependUnderscore style naming for internal contract functions, internal top-level parameters, and function parameters with naming collisions.
3. Picking up stale issues by other authors is acceptable; communicate with them beforehand and include co-authors in commits.
4. Squash commits when possible for clean and efficient reviews. Merged PRs will be squashed into 1 commit.

## Community

Stay updated and engage with other contributors and users:

- [Website](https://www.sperax.io/)
- [Telegram](https://t.me/SperaxUSD)
- [Discord](https://discord.com/invite/cFdcvj9jMm)
- [Twitter](https://twitter.com/SperaxUSD)
- [Medium](https://medium.com/sperax)

## License

By contributing to our protocol, you agree that your contributions will be licensed under the [MIT LICENSE](https://opensource.org/license/mit/) associated with the project.

Thank you for your interest in the USDs Protocol. We look forward to your contributions and appreciate your support in making our project even better!