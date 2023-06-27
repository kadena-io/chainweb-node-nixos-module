# - Create the database and start filling the database with blocks:
#   run `chainweb-data server` -m (with other necessary options). Wait a couple
#   of minutes and kill chainweb-data.
# - Fill all the blocks:
#   run chainweb-data fill (with other necessary options, and --disable-indexes
#   if the server doesn't need to be running)
# - After the `fill` operation finishes, you can run `server` again with the
#   `-f` option and it will automatically fill once a day to populate the DB with
#   missing blocks.

{ config, lib, ... }:

with lib;

let
  cfg = config.services.chainweb-data;

  topLevelOptions = {
    dbString = mkOption {

    };

    dbHost = mkOption {

    };

    dbPort = mkOption {

    };

    dbUser = mkOption {

    };

    # TODO: integrate with sops/make this option a file
    #dbPass = mkOption {
    #
    #};

    dbName = mkOption {

    };

    dbDir = mkOption {

    };

    serviceHttps = mkEnableOption (lib.mdDoc ''
      Use HTTPS to connect to the service API (instead of HTTP)
    '');

    serviceHost = mkOption {

    };

    servicePort = mkOption {

    };

    p2pHost = mkOption {

    };

    p2pPort = mkOption {

    };

    logLevel = mkOption {

    };

    runMigration = mkEnableOption (lib.mdDoc ''
      Run DB migration
    '');

    ignoreSchemaDiff = mkEnableOption (lib.mdDoc ''
      Ignore any unexpected differences in the database schema
    '');

    migrationsFolder = mkOption {

    };
  };

  serverOptions = {
    port = mkOption {
      description = lib.mdDoc ''
        Port the server will listen on
      '';
    };

    runFill = mkEnableOption (lib.mdDoc ''
      Run fill operation once a day to fill gaps
    '');

    delayMicros = mkOption {
      type = types.nullOr types.int;
      description = lib.mdDoc ''
        Number of microseconds to delay between queries to the node.
        If null, there is no delay.
      '';
    };

    noListen = mkEnableOption (lib.mdDoc ''
      Disable node listener
    '');
  };

  fillOptions = {
    delayMicros = mkOption {
      type = types.nullOr types.int;
      description = lib.mdDoc ''
        Number of microseconds to delay between queries to the node.
        If null, there is no delay.
      '';
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
        default = pkgs.chainweb-data;
      };

      command = mkOption {
        type = types.enum [
          "backfill-transfers"
          "check-schema"
          "fill"
          "fill-events"
          "listen"
          "migrate"
          "richlist"
          "server"
          "single"
        ];
        default = "server";
      };


    };
  };

  ### Implementation
  config = mkIf cfg.enable {

    systemd.services.chainweb-data = {
      description = "Chainweb Data";

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
              (mkYesNoFlag cfg.validateHashesOnReplay "validateHashesOnReplay")
              "--log-level ${cfg.logLevel}"
              "--log-format ${cfg.logFormat}"
              "--log-handle ${cfg.logHandle}"
              "--chainweb-version ${cfg.chainwebVersion}"
              (mkYesNoFlag cfg.headerStream "header-stream")
              (mkEnableFlag cfg.txReintroduction "tx-reintro")
              (mkYesNoFlag cfg.allowReadsInLocal "allowReadsInLocal")
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
