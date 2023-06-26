std:

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.chainweb-node;

  mkEnableFlag = enabled: name: if enabled then "--enable-${name}" else "--disable-${name}";
  mkYesNoFlag = do: name: if do then "--${name}" else "--no-${name}";
  mkIfNotNull = arg: name: std.string.optional (!(builtins.isNull arg)) "--${name}=${arg}";

  toStr = builtins.toString;

  /*
  UID/GID

  # foldl
  #   (fac: acc: if acc > 399 && acc < 1000 then acc else fac * acc) # valid uid/gid range
  #   1
  #   (take 3 (prime_factors (to_ascii "chainweb")))
  */
  id = 418;

  strHasSuffix = pattern: mkOptionType {
    name = "strHasSuffix ${std.string.escapeNixString pattern}";
    description = "string with the suffix \"${pattern}\"";
    check = x: types.str.check x && std.string.hasSuffix pattern x;
  };

  strHasPrefix = pattern: mkOptionType {
    name = "strHasPrefix ${std.string.escapeNixString pattern}";
    description = "string with the prefix \"${pattern}\"";
    check = x: types.str.check x && std.string.hasPrefix pattern x;
  };

  knownGraphType = mkOptionType {
    name = "ChainwebKnownGraph";
    description = "chainweb-node KnownGraph type";
    check = x: types.nonEmptyStr.check x && std.list.elem x ["singleton" "pair" "triangle" "peterson" "twenty" "hoffman"];
  };

  chainwebVersionType = mkOptionType {
    name = "ChainwebVersion";
    description = "chainweb-node graph version";
    check = x:
      let xs = std.regex.splitOn "-" x;
          version = std.list.index xs 0;
          graph1 = std.list.index xs 1;
          graph2 = std.list.index xs 2;
          checkSize = sz:
            if std.list.length xs == sz
            then true
            else throw "chainwebVersionType: mismatched size. Expected ${toStr sz}";
          checkVersion = std.optional.match version {
            nothing = false;
            just = v:
              if std.list.elem v ["development" "testnet04" "mainnet01"]
              then checkSize 1
              else

              if std.list.elem v ["test" "powConsensus" "timedCPM" "fastTimedCPM"]
              then std.optional.match graph1 {
                nothing = false;
                just = g1: checkSize 2 && knownGraphType.check g1;
              }
              else

              if v == "timedConsensus"
              then std.optional.match (std.applicative.lift2 std.tuple2 graph1 graph2) {
                nothing = false;
                just = gs: checkSize 3 && knownGraphType.check gs._0 && knownGraphType.check gs._1;
              }
              else false;
          };
      in types.nonEmptyStr.check x && checkVersion;
    };

  mkConfigFile = logLevel: extraConfig: pkgs.writeText "${cfg.dataDir}/chainweb-node.config" (std.serde.toJSON {
    logging = {
      telemetryBackend = {
        enabled = false;
        configuration = {
          handle = "stdout";
          color = "auto";
          format = "text";
        };
      };
    };

    backend = {
      handle = "stdout";
      color = "auto";
      format = "text";
    };

    logger = {
      log_level = logLevel;
    };

    filter = {
      rules = [
        { key = "component";
          value = "cut-monitor";
          level = "info";
        }
        { key = "component";
          value = "pact";
          level = "info";
        }
      ];
      default = logLevel;
    };

    chainweb = extraConfig;
  });

  replayConfigFile = mkConfigFile "info" {
    allowReadsInLocal = true;
    headerStream = true;
    onlySyncPact = true;
    gasLog = true;
    cuts = {
      pruneChainDatabase = "headers-checked";
    };
    transactionIndex = {
      enabled = false;
    };
    p2p = {
      private = true;
      ignoreBootstrapNodes = true;
      bootstrapReachability = 0;
    };
  };
in
{
  ### Configuration
  options = {
    services.chainweb-node = {
      enable = mkEnableOption (lib.mdDoc "Chainweb Node");

      package = mkOption {
        type = types.package;
        default = pkgs.chainweb-node;
        example = literalExpression "pkg.chainweb-node";
        description = lib.mdDoc ''
          Chainweb Node package to use.

          Note that this module does not come bundled with an overlay providing
          chainweb-node; you are expected to provide it yourself.
        '';
      };

      configFile = mkOption {
        type = types.nullOr types.path;
        example = "chainweb-node.config.json";
        default = null;
        description = lib.mdDoc ''
          Configuration file in YAML or JSON format.
        '';
      };

      replay = mkEnableOption (lib.mdDoc ''
        Run a replay, disregarding all customisation.
        Runs as a one-shot service.
      '');

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/chainweb-node";
        example = "/var/lib/chainweb-node";
        description = lib.mdDoc ''
          The data directory for chainweb-node. If left as the default value
          this directory will automatically be created before the node starts,
          otherwise the sysadmin is responsible for ensuring the directory exists
          with appropriate ownership and permissions.
        '';
      };

      subdir = mkOption {
        type = types.nonEmptyStr;
        default = "${cfg.chainwebVersion}";
        example = "mainnet01";
        description = lib.mdDoc ''
          The subdirectory under `dataDir` for the data files of a particular chainwebVersion.
        '';
      };

      enableNodeMining = mkEnableOption (lib.mdDoc "Whether to enable node mining.");

      bootstrapReachability = mkOption {
        type = types.numbers.between 0 1;
        default = 0.5;
        example = 0;
        description = lib.mdDoc ''
          The fraction of the bootstrap nodes that must be reachable and must
          be able to reach this node on startup.
        '';
      };

      p2pPort = mkOption {
        type = types.port;
        default = 1789;
        description = lib.mdDoc ''
          The port number for P2P communication.
        '';
      };

      servicePort = mkOption {
        type = types.port;
        default = 1848;
        description = lib.mdDoc ''
          The port number for the Service API.
        '';
      };

      onlySyncPact = mkEnableOption (lib.mdDoc ''
        Terminate after synchronizing the pact databases to
        the latest cut.
      '');

      logLevel = mkOption {
        type = types.enum ["quiet" "error" "warn" "info" "debug"];
        default = "info";
        description = lib.mdDoc ''
          Severity threshold for log messages.
        '';
      };

      logFormat = mkOption {
        type = types.enum ["text" "json"];
        default = "text";
        description = lib.mdDoc ''
          Format that is used for writing logs to file handles.
        '';
      };

      logHandle = mkOption {
        type = types.oneOf
          [ (types.enum ["stdout" "stderr"])
            (strHasPrefix "file:")
            (strHasPrefix "es:")
          ];
        default = "stderr";
        description = lib.mdDoc ''
          Handle where the logs are written.

          stdout|stderr|file:<FILENAME>|es:[APIKEY]:<URL>
        '';
      };

      chainwebVersion = mkOption {
        type = chainwebVersionType;
        default = "mainnet01";
        description = lib.mdDoc ''
          The chainweb version that this node is using.
        '';
      };

      headerStream = mkEnableOption (lib.mdDoc ''
        Whether to enable an endpoint for streaming block updates
      '');

      txReintroduction = mkEnableOption (lib.mdDoc ''
        Whether to enable transaction reintroduction from losing forks
      '');

      printConfigAs = mkOption {
        type = types.nullOr (types.enum ["full" "minimal" "diff"]);
        default = null;
        description = lib.mdDoc ''
          If non-null, print the parsed configuration to stdout and exit.
        '';
      };
    };
  };

  ### Implementation
  config = mkIf cfg.enable {

    systemd.services.chainweb-node = {
      description = "Chainweb Node";

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      preStart = ''
        if ! test -e ${cfg.dataDir}; then
          mkdir -p ${cfg.dataDir}/${cfg.subdir}
        fi
      '';

      serviceConfig = {
        User = "chainweb";
        Group = "chainweb";

        ExecStart =
          let
            sep = " \\\n  ";
            exe = "${cfg.package}/bin/chainweb-node";
            arg = args: std.string.concatSep sep ([exe] ++ args);

          in

          if cfg.replay
          then arg
            [
              "--config-file ${replayConfigFile}"
              "--database-directory ${cfg.dataDir}/${cfg.subdir}"
              (mkEnableFlag cfg.enableNodeMining "node-mining")
              "--p2p-port ${toStr cfg.p2pPort}"
              "--service-port ${toStr cfg.servicePort}"
            ]
          else arg
            [
              (mkIfNotNull cfg.configFile "config-file")
              (mkIfNotNull cfg.printConfigAs "print-config-as")
              "--database-directory ${cfg.dataDir}/${cfg.subdir}"
              (mkEnableFlag cfg.enableNodeMining "node-mining")
              "--bootstrap-reachability ${toStr cfg.bootstrapReachability}"
              "--p2p-port ${toStr cfg.p2pPort}"
              "--service-port ${toStr cfg.servicePort}"
              (mkYesNoFlag cfg.onlySyncPact "only-sync-pact")
              "--log-level ${cfg.logLevel}"
              "--log-format ${cfg.logFormat}"
              "--log-handle ${cfg.logHandle}"
              "--chainweb-version ${cfg.chainwebVersion}"
              (mkYesNoFlag cfg.headerStream "header-stream")
              (mkEnableFlag cfg.txReintroduction "tx-reintro")
            ];

        ExecReload = ''
          ${pkgs.coreutils}/bin/kill -HUP $MAINPID
        '';

        KillSignal = "SIGINT";
        KillMode = "mixed";

        TimeoutSec = 120;
      };
    };

    users = {
      users.chainweb = {
        name = "chainweb";
        uid = id;
        group = "chainweb";
        description = "chainweb user";
        home = cfg.dataDir;
        useDefaultShell = true;
        isSystemUser = true;
        createHome = true;
      };

      groups.chainweb.gid = id;
    };

    environment.systemPackages = [
      cfg.package
    ];

    networking.firewall.allowedTCPPorts = [ cfg.p2pPort ];
  };
}
