# taws Package
#
# Terminal UI for AWS (taws) - A terminal-based AWS resource viewer and manager.
# Built with Rust using rustPlatform.buildRustPackage.
#
# This package is automatically updated via GitHub Actions when new releases
# are published to the upstream repository.

{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  stdenv,
  libiconv,
}:

rustPlatform.buildRustPackage rec {
  pname = "taws";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "huseyinbabal";
    repo = "taws";
    rev = "v${version}";
    hash = "sha256-DonU25/cUsHTD6Ub3SKeSdGDchScFVcHrE/KBK3nvok=";
  };

  cargoHash = "sha256-rXLptpif2td/PvSLwdlPR8oLY1cqwNgOU2RzU/wCbSk=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    openssl
  ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
    libiconv
  ];

  # Skip tests as they require AWS credentials
  doCheck = false;

  meta = with lib; {
    description = "Terminal UI for AWS (taws) - A terminal-based AWS resource viewer and manager";
    homepage = "https://github.com/huseyinbabal/taws";
    license = licenses.mit;
    maintainers = [ ];  # Add yourself here
    mainProgram = "taws";
    platforms = platforms.unix;
  };
}
