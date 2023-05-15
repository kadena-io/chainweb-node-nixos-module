std:

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.chainweb-node;

  mkEnableFlag = enabled: name: if enabled then "--enable-${name}" else "--disable-${name}";
  mkYesNoFlag = do: name: if do then "--${name}" else "--no-${name}";
  mkFlagIfNotNull = arg: name: std.string.optional (!(builtins.isNull arg)) "--${name}=${arg}";

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
in
{
  inherit mkEnableFlag mkYesNoFlag mkFlagIfNotNull;

  inherit toStr id;

  inherit strHasSuffix strHasPrefix knownGraphType chainwebVersionType;
}
/*
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
*/
