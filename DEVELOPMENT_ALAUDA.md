# Tkn alauda Branch Development Guide

## Background

Previously, `tkn` was used as a general-purpose CLI across multiple plugins, each needing to fix vulnerabilities in `tkn` independently.

To avoid duplicated effort, we forked the current repository from [tkn](https://github.com/tektoncd/cli.git) and maintain it through branches named `alauda-vx.xx.xx`.

We use [renovate](https://gitlab-ce.alauda.cn/devops/tech-research/renovate/-/blob/main/docs/quick-start/0002-quick-start.md) to automatically fix vulnerabilities in corresponding versions.

## Repository Structure

Based on the original code, the following content has been added:

- [alauda-auto-tag.yaml](./.github/workflows/alauda-auto-tag.yaml): Automatically tags and triggers goreleaser when a PR is merged into the `alauda-vx.xx.xx` branch
- [release-alauda.yaml](./.github/workflows/release-alauda.yaml): Supports triggering goreleaser manually or upon tag updates (this pipeline won't be triggered if a tag is created automatically within an action, as actions are designed not to recursively trigger multiple actions)
- [reusable-release-alauda.yaml](./.github/workflows/reusable-release-alauda.yaml): Executes goreleaser to create a release
- [scan-alauda.yaml](.github/workflows/scan-alauda.yaml): Runs trivy to scan for vulnerabilities (`rootfs` scans Go binaries)
- [.goreleaser-alauda.yml](.goreleaser-alauda.yml): Configuration file for releasing alauda versions

## Special Modifications

1. The official project does not provide GitHub Actions for automated testing, so we wrote our own [test-alauda.yaml](.github/workflows/test-alauda.yaml) that runs `make test`

## Pipelines

### Triggered When Pull Request is Submitted

- [test-alauda.yaml](.github/workflows/test-alauda.yaml): Executes the official tests using `make test`

### Triggered When Merged into alauda-vx.xx.xx Branch

- [alauda-auto-tag.yaml](.github/workflows/alauda-auto-tag.yaml): Automatically tags and triggers goreleaser
- [reusable-release-alauda.yaml](.github/workflows/reusable-release-alauda.yaml): Executes goreleaser to create a release (triggered by `alauda-auto-tag.yaml`)

### Scheduled or Manually Triggered

- [scan-alauda.yaml](.github/workflows/scan-alauda.yaml): Runs trivy to scan for vulnerabilities (`rootfs` scans Go binaries)

### Others

Other pipelines maintained officially have not been modified; some irrelevant pipelines have been disabled on the Actions page.

## Renovate Vulnerability Fixing Mechanism

The renovate configuration file is [renovate.json](https://github.com/AlaudaDevops/trivy/blob/main/renovate.json)

1. renovate detects vulnerabilities in the branch and creates a PR to fix them
2. Tests are automatically executed on the PR
3. After all tests pass, renovate automatically merges the PR
4. After the branch is updated, an action automatically tags the commit (e.g., v0.62.1-alauda-0, where both the patch version and the last digit increment)
5. goreleaser automatically publishes a release based on the tag

## Maintenance Plan

When upgrading to a new version, follow these steps:

1. Create an alauda branch from the corresponding tag, e.g., the `v0.62.1` tag corresponds to the `alauda-v0.62.1` branch
2. Cherry-pick previous alauda branch changes to the new branch and push

Renovate automatic fixing mechanism:
1. After renovate creates a PR, pipelines run automatically; if all tests pass, the PR will be merged automatically
2. After merging into the `alauda-v0.62.1` branch, goreleaser will automatically create a `v0.62.2-alauda-0` release (note: not `v0.62.1-alauda-0`, because only a newer version allows renovate to detect it)
3. renovate configured in other plugins will automatically fetch artifacts from the release according to its configuration
