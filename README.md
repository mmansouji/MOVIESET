# MOVIESET

TVMaze data collection pipeline for OscarTV.

The GitHub Actions workflow downloads TVMaze episode JSON files on GitHub-hosted
runners and transfers them through Tailscale + SSH to the OscarTV data host.

The workflow does not use GitHub Actions artifacts for the dataset.
Existing JSON files on the destination host are preserved.
