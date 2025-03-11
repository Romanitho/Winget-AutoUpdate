# Contribution Guide

Thank you for your interest in contributing to this project!

## Branches

- **`main`**: Contains the production code and is locked for direct commits.
- **`develop`**: Contains the code under development for the next release.
- **`feature/<name>`**: Used to develop new features.
- **`hotfix/<name>`**: Used to fix bugs.

## Protection of the `main` Branch

To ensure the quality and stability of the production code, contributors should follow these steps:
- Create a new branch from `develop` for their feature,
- Once the work is complete, open a pull request
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
   - Each new feature should be developed in a `feature` branch.
   - A PR should be requested to merge the `feature` branch into `develop`.

4. **Release Creation**:
   - Once a new release needs to be created, a GitHub Action is manually triggered to create a release branch from the develop branch.
   - A Pull Request is automatically issued to merge the release branch into the main branch.
   - Final reviews and validations are performed at this stage.
   - Merging the release branch into the main branch automatically creates a new release via another GitHub Action.
