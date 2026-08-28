Goal: Run Pi-hole (https://pi-hole.net/) locally on Macos Tahoe (Apple M5) in such a way that it can be used as the DNS resolver for the localhost.

Approach tried and failed: The first approach was to run the `pihole` repo from `goatatwork` - https://github.com/goatatwork/pihole. Ports would be mapped and everything would be great. Unfortunately, it isn't that straight forward with Docker containers on Macos due to the hidden (kind of) virtual machine that's really running the containers. Networking become 'an issue'.

Your mission: Find a solution. You have docker available to you. You have limactl available to you. You have the gh github cli available to you. The intent is to find and implement a solution while also setting up the project to be reproducible on other Macos machines. A procedure to update the pihole software itself should be at least documented in the README.md, and built in if easily accomplished.

