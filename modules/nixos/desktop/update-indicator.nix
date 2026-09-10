# itera's update indicator: a DankMaterialShell dank-bar widget that says when the
# itera repository has moved on from the revision this machine was built with.
#
# A machine running itera does not track itera directly. It runs a downstream
# config flake (`itera.update.flake`, e.g. `github:me/my-config`) which pins itera
# in ITS flake.lock, so `itera update` — `nh os switch <that flake> --refresh` —
# only ever fetches the newest pushed revision of the config repo. New itera
# commits arrive when, and only when, somebody bumps that lock and pushes it.
# Nothing surfaced that gap, so framework work could sit unpicked-up indefinitely
# with no signal anywhere on the desktop.
#
# The comparison is cheap because half of it is already known at build time: the
# itera revision baked into this system is `self.rev`, which this module writes
# into the plugin's settings. The widget therefore needs no checkout on disk, no
# flake evaluation and no privileges — just `git ls-remote` against the upstream.
#
# Deliberately READ-ONLY. Everything it could usefully automate — bumping the
# downstream lock, pushing it, rebuilding — spans a git push and a privileged
# rebuild with a lot of partial-failure states in between, so acting on the signal
# stays a deliberate step at a terminal. The popout shows the command; it does not
# run it. The only thing this battery ever executes is a helper that prints JSON.
#
# The one externally-visible behaviour: with the desktop on, every consumer's
# shell polls github.com unauthenticated every half hour. `enable = false` and
# `pollIntervalSeconds` are the knobs.
#
# Opt-OUT (default ON), and additionally gated on the DMS battery — the widget has
# nowhere to render without it.
{
  config,
  lib,
  pkgs,
  iteraInputs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool ints str;

  cfg = config.itera.desktop.updateIndicator;

  # The itera revision this system was built with. `self.rev` is absent when itera
  # is consumed from a dirty checkout — deliberately NOT falling back to
  # `dirtyRev`, whose `-dirty` suffix is not a commit and would compare unequal to
  # every remote head forever. Empty means "unknown", which the widget renders as
  # its own state rather than as an available update.
  lockedRev = iteraInputs.self.rev or "";

  # Prints exactly one JSON object on stdout and nothing else. Shipped on PATH as
  # well as wired to the widget: a status indicator you cannot interrogate by hand
  # is miserable to debug, and the same reasoning applies here as to
  # `itera-screencast-chooser` next door.
  checkTool = pkgs.writeShellApplication {
    name = "itera-update-check";
    runtimeInputs = [
      pkgs.git
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      repo=${lib.escapeShellArg cfg.repository}
      branch=${lib.escapeShellArg cfg.branch}
      locked=${lib.escapeShellArg lockedRev}

      remote=""
      # -1 is "ahead, but by an unknown number of commits": the count is a
      # best-effort extra, while the ahead/not-ahead answer only needs two revs.
      behind=-1
      commits='[]'
      err=""

      # Is a newer generation staged for the next boot? Two readlinks, no
      # privileges, and unrelated to the network — so it is still answerable when
      # everything below fails.
      boot=false
      if [ "$(readlink -f /run/booted-system 2>/dev/null || true)" \
        != "$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)" ]; then
        boot=true
      fi

      if [ -z "$locked" ]; then
        err="this system was built from a dirty itera checkout, so there is no revision to compare"
      else
        remote=$(timeout 20 git ls-remote --heads "$repo" "$branch" 2>/dev/null | head -n1 | cut -f1) || true
        if [ -z "$remote" ]; then
          err="could not reach $repo"
        elif [ "$remote" = "$locked" ]; then
          behind=0
        else
          # The count and the commit list come from GitHub's compare API. It is
          # best-effort on purpose: unauthenticated (60 req/hr per IP, against a
          # poll that only asks when it is already behind), GitHub-only, and not
          # load-bearing — the answer that drives the widget was settled above.
          slug=""
          case "$repo" in
            https://github.com/*)
              slug=''${repo#https://github.com/}
              slug=''${slug%.git}
              ;;
          esac
          if [ -n "$slug" ]; then
            body=$(timeout 20 curl -fsSL -H 'Accept: application/vnd.github+json' \
              "https://api.github.com/repos/$slug/compare/$locked...$remote" 2>/dev/null) || body=""
            if [ -n "$body" ]; then
              behind=$(printf '%s' "$body" | jq '.ahead_by // -1') || behind=-1
              # GitHub returns the compare oldest-first; take the newest ten and
              # flip them so the popout reads newest at the top.
              commits=$(printf '%s' "$body" | jq -c \
                '[(.commits // [])[-10:][] | {sha: .sha[0:7], subject: (.commit.message | split("\n")[0])}] | reverse') || commits='[]'
            fi
          fi
        fi
      fi

      jq -n \
        --arg lockedRev "$locked" \
        --arg remoteRev "$remote" \
        --arg error "$err" \
        --argjson behindBy "$behind" \
        --argjson commits "$commits" \
        --argjson bootPending "$boot" \
        --argjson checkedAt "$(date +%s)" \
        '{ $lockedRev, $remoteRev, $behindBy, $commits, $bootPending, $checkedAt, $error }'
    '';
  };
in
{
  options.itera.desktop.updateIndicator = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Show a DankMaterialShell dank-bar widget when the itera repository is
        ahead of the revision this system was built with. On by default whenever
        {option}`itera.enable` and {option}`itera.desktop.dankMaterialShell.enable`
        are set; set to `false` to drop the widget (and with it the periodic
        request to {option}`itera.desktop.updateIndicator.repository`).

        The widget only reports. It never bumps a lock, pushes, or rebuilds.
      '';
    };

    repository = mkOption {
      type = str;
      default = "https://github.com/lcleveland/itera";
      example = "https://github.com/me/itera-fork";
      description = ''
        The itera repository to compare against — an HTTPS git URL, since it is
        fetched with {command}`git ls-remote` and no credentials. Point this at
        your fork if you build from one, so the widget tracks the repository your
        {file}`flake.lock` actually pins.

        A `https://github.com/…` URL additionally gets the commit count and
        subject list from GitHub's compare API; any other host still gets the
        ahead/not-ahead answer, just without the detail.
      '';
    };

    branch = mkOption {
      type = str;
      default = "main";
      example = "develop";
      description = ''
        Which branch of {option}`itera.desktop.updateIndicator.repository` counts
        as "the newest itera".
      '';
    };

    pollIntervalSeconds = mkOption {
      type = ints.positive;
      default = 1800;
      example = 3600;
      description = ''
        How often to re-check, in seconds. The widget floors this at 60 seconds:
        it is a background poller against somebody else's server, and the answer
        changes on the order of hours.
      '';
    };

    hideWhenUpToDate = mkOption {
      type = bool;
      default = false;
      description = ''
        Collapse the bar pill entirely while the system is current, so it appears
        only when there is something to say. A staged-but-not-booted generation
        and a failed check still show — both are things worth being told about.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable && config.itera.desktop.dankMaterialShell.enable) {
    environment.systemPackages = [ checkTool ];

    # Registered like the ipIndicator and screencastChooser plugins next door, so
    # it is installed AND enabled declaratively — no Settings → Plugins → Scan
    # step. The attribute name must match `plugin.json`'s `id`: the hjem renderer
    # keys both the plugin directory and the plugin_settings.json entry off it,
    # while DMS looks settings up by id.
    #
    # These settings are one-way. itera symlinks plugin_settings.json out of the
    # store (clobber = true), so the plugin cannot write them back — which is why
    # the plugin ships no settings component and every knob is an option above.
    itera.programs.dankMaterialShell.plugins.iteraUpdate = {
      src = mkDefault ../../../pkgs/dms-itera-update;
      settings = mkDefault {
        inherit lockedRev;
        lockedRevShort = iteraInputs.self.shortRev or "";
        lockedDate = iteraInputs.self.lastModified or 0;
        inherit (cfg)
          repository
          branch
          pollIntervalSeconds
          hideWhenUpToDate
          ;
        checkCommand = lib.getExe checkTool;
      };
    };
  };
}
