# Contribution Guide

Thank you for your interest in contributing to this project!

## Before Opening a Pull Request

To keep the project consistent and avoid wasted effort, **every pull request must be linked to an issue**.

1. **Open an issue first** describing the bug or the change you would like to make, so it can be discussed before any code is written.
2. **Reference the issue in your pull request description** using `Fixes #123`, `Closes #123` or `Resolves #123`.

Pull requests that are not linked to an issue will be closed automatically.
Inactive pull requests may also be closed after a period of inactivity.

## One Pull Request, One Change

Keep each pull request focused on a single purpose: one feature, one fix or one refactoring.

- **Do not mix unrelated changes** (e.g. a new feature + formatting + a bug fix elsewhere).
- **Separate refactoring from functional changes.** If some code needs to be reworked first, do it in a dedicated pull request.
- **Stay within the scope of the linked issue.** If you find something else to improve, open a new issue.

All-in-one pull requests are hard to review, test and revert, and will not be accepted.

## Branches

- **`main`**: Contains the production code and is locked for direct commits.
- **`develop`**: Contains the code under development for the next release.
- **`feature/<name>`**: Used to develop new features.
- **`hotfix/<name>`**: Used to fix bugs.

## Protection of the `main` Branch

To ensure the quality and stability of the production code, contributors should follow these steps:
- Make sure the change is covered by an issue (see [Before Opening a Pull Request](#before-opening-a-pull-request))
- Create a new branch from `develop` for their feature
- Once the work is complete, open a pull request targeting `develop` and referencing the issue
- Ensure that the pull request has a clear title
- The pull request must pass all tests and receive approval from reviewers

This workflow ensures that the `main` branch remains stable and production-ready.

## Use Gitflow as much as possible

![Hotfix_branches](https://github.com/user-attachments/assets/d1b2efe3-3c2e-47c1-8e39-66bf93c34efa)

### GitFlow Process

1. **Main Branches**:
   - `main`: The primary branch containing the official release history.
   - `develop`: The branch where the latest development changes accumulate.

2. **Branch Types in our Workflow**:
   - `feature/<name>`: For contributors to develop new features.
   - `hotfix/<name>`: For contributors to fix critical bugs.
   - `release/<version>`: Automatically created by GitHub Actions for preparing new production releases (not created directly by contributors).

3. **Pull Request Process for Contributors**:
   - Each new feature should be developed in a dedicated `feature` branch (one feature per branch).
   - A PR should be requested to merge the `feature` branch into `develop`, referencing the issue.

4. **Release Creation**:
   - Once a new release needs to be created, a GitHub Action is manually triggered to create a release branch from the develop branch.
   - A Pull Request is automatically issued to merge the release branch into the main branch.
   - Final reviews and validations are performed at this stage.
   - Merging the release branch into the main branch automatically creates a new release via another GitHub Action.
