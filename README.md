# taws-nix

Always up-to-date Nix package for [taws](https://github.com/huseyinbabal/taws) - Terminal UI for AWS.

**Automatically updated hourly** to ensure you always have the latest taws version.

## Quick Start

```bash
# Run directly without installing
nix run github:caseymatt/taws-nix

# Install to your profile
nix profile install github:caseymatt/taws-nix
```

## Installation

### Using Flake (Recommended)

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    taws.url = "github:caseymatt/taws-nix";
  };

  outputs = { self, nixpkgs, taws, ... }: {
    # Use the overlay
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        {
          nixpkgs.overlays = [ taws.overlays.default ];
          environment.systemPackages = [ pkgs.taws ];
        }
      ];
    };
  };
}
```

### Using Home Manager

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    taws.url = "github:caseymatt/taws-nix";
  };

  outputs = { self, nixpkgs, home-manager, taws, ... }: {
    homeConfigurations."username" = home-manager.lib.homeManagerConfiguration {
      modules = [
        {
          nixpkgs.overlays = [ taws.overlays.default ];
          home.packages = [ pkgs.taws ];
        }
      ];
    };
  };
}
```

Or use the Home Manager module:

```nix
{
  imports = [ taws.homeManagerModules.default ];
  programs.taws.enable = true;
}
```

## Version Pinning

Pin to specific taws versions using git refs:

| Tag | Example | Behavior |
|-----|---------|----------|
| `vX.Y.Z` | `v1.1.2` | Exact version (immutable) |
| `vX` | `v1` | Latest in major series (updates) |
| `latest` | `latest` | Always newest version |

```nix
{
  inputs = {
    # Always latest
    taws.url = "github:caseymatt/taws-nix";

    # Pin to exact version
    taws.url = "github:caseymatt/taws-nix?ref=v1.1.2";

    # Track major version
    taws.url = "github:caseymatt/taws-nix?ref=v1";
  };
}
```

## Development

```bash
# Clone the repository
git clone https://github.com/caseymatt/taws-nix
cd taws-nix

# Build
nix build

# Test
./result/bin/taws --version

# Check for updates
./scripts/update-version.sh --check

# Update to latest
./scripts/update-version.sh

# Update to specific version
./scripts/update-version.sh --version 1.1.2

# Enter dev shell
nix develop
```

## How It Works

1. **Hourly GitHub Actions** checks for new taws releases
2. When a new version is found:
   - Updates `version` in `package.nix`
   - Fetches new source hash via `nix-prefetch-github`
   - Determines `cargoHash` by triggering a build
   - Creates a PR with all changes
3. PR auto-merges if CI passes
4. Version tags (`vX.Y.Z`, `vX`, `latest`) are automatically created

## License

The Nix packaging is MIT licensed. taws itself is MIT licensed by [Huseyin Babal](https://github.com/huseyinbabal).
