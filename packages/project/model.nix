{ lib }:

let
  loadProjectCatalog =
    dir:
    let
      walk =
        prefix: path:
        lib.concatMap (
          entry:
          let
            entryType = (builtins.readDir path).${entry};
            entryPath = path + "/${entry}";
          in
          if entryType == "directory" then
            let
              projectFile = entryPath + "/project.nix";
              projectName = lib.concatStringsSep "." (prefix ++ [ entry ]);
            in
            lib.optional (builtins.pathExists projectFile) {
              name = projectName;
              value = import projectFile;
            }
            ++ walk (prefix ++ [ entry ]) entryPath
          else
            [ ]
        ) (lib.attrNames (builtins.readDir path));
    in
    lib.listToAttrs (walk [ ] dir);

  mkProjectModel =
    {
      items ? { },
      catalogDir ? null,
      userPrefix ? "usr.prj_",
      workDirName ? "src",
    }:
    let
      normalizeRepo = projectName: project: repoName: repo: {
        name = repoName;
        aliases = repo.aliases or [ ];
        path = if (repo.path or null) == null then "repo.${repoName}" else repo.path;
        mode = repo.mode or "0750";
        primary = repo.primary or false;
        git = {
          url = repo.git.url or null;
          remote = repo.git.remote or "origin";
          branch = repo.git.branch or null;
        };
        description = repo.description or null;
      };

      normalizeProject = name: project: {
        user = project.user or null;
        aliases = project.aliases or [ ];
        home = project.home or null;
        homeMode = project.homeMode or "0750";
        workDir = project.workDir or null;
        workDirMode = project.workDirMode or "0750";
        defaultRepo = project.defaultRepo or null;
        repos = lib.mapAttrs (normalizeRepo name project) (
          if (project.repos or { }) != { } then project.repos else project.checkouts or { }
        );
        hasReposAndCheckouts = (project.repos or { }) != { } && (project.checkouts or { }) != { };
        scope = {
          enable = project.scope.enable or false;
          includeDescendants = project.scope.includeDescendants or false;
          include = project.scope.include or [ ];
        };
      };

      catalogItems = if catalogDir == null then { } else loadProjectCatalog catalogDir;
      projectItems = lib.mapAttrs normalizeProject (catalogItems // items);
      projectNames = lib.attrNames projectItems;
      projectLookupNames = lib.concatMap (name: [ name ] ++ projectItems.${name}.aliases) projectNames;

      projectUser = name: project: if project.user != null then project.user else "${userPrefix}${name}";
      projectHome =
        name: project: if project.home != null then project.home else "/home/${projectUser name project}";
      projectWorkDir =
        name: project:
        if project.workDir != null then project.workDir else "${projectHome name project}/${workDirName}";
      projectUsers = map (name: projectUser name projectItems.${name}) projectNames;

      projectHasPrefix = prefix: name: lib.hasPrefix "${prefix}." name;
      scopeIncludedProjects =
        name:
        let
          scope = projectItems.${name}.scope;
        in
        lib.unique (
          lib.optionals scope.includeDescendants (lib.filter (projectHasPrefix name) projectNames)
          ++ scope.include
        );

      repoPath =
        projectName: project: repoName: repo:
        if lib.hasPrefix "/" repo.path then
          repo.path
        else if repo.path == "." then
          projectWorkDir projectName project
        else
          "${projectWorkDir projectName project}/${repo.path}";

      declaredRepoTargets =
        name: project:
        lib.mapAttrs (
          repoName: repo:
          repo
          // {
            project = name;
            ownerUser = projectUser name project;
            home = projectHome name project;
            path = repoPath name project repoName repo;
            synthetic = false;
          }
        ) project.repos;

      compatRepoTarget =
        name: project:
        let
          workDir = projectWorkDir name project;
        in
        {
          name = "default";
          aliases = [ ];
          path = workDir;
          mode = project.workDirMode;
          primary = true;
          synthetic = true;
          git = {
            url = null;
            remote = "origin";
            branch = null;
          };
          description = null;
          project = name;
          ownerUser = projectUser name project;
          home = projectHome name project;
        };

      projectRepoTargets =
        name: project:
        if project.repos == { } then
          { default = compatRepoTarget name project; }
        else
          declaredRepoTargets name project;

      projectDefaultTarget =
        name: project:
        let
          targets = projectRepoTargets name project;
          targetNames = lib.attrNames targets;
          primaryTargets = lib.filter (repoName: targets.${repoName}.primary) targetNames;
        in
        if project.repos == { } then
          "default"
        else if project.defaultRepo != null then
          project.defaultRepo
        else if lib.length targetNames == 1 then
          lib.head targetNames
        else if lib.length primaryTargets == 1 then
          lib.head primaryTargets
        else
          null;

      projectEntryDir =
        name: project:
        let
          defaultTarget = projectDefaultTarget name project;
        in
        if defaultTarget == null then
          projectWorkDir name project
        else
          (projectRepoTargets name project).${defaultTarget}.path;

      enrichedProjectItems = lib.mapAttrs (
        name: project:
        (removeAttrs project [ "hasReposAndCheckouts" ])
        // {
          repoTargets = projectRepoTargets name project;
          defaultTarget = projectDefaultTarget name project;
        }
      ) projectItems;

      declaredRepoTargetRecords = lib.concatMap (
        name:
        let
          project = projectItems.${name};
          targets = declaredRepoTargets name project;
        in
        map (repoName: targets.${repoName}) (lib.attrNames targets)
      ) projectNames;

      repoLookupRecords = lib.concatMap (
        target: map (lookupName: target // { lookupName = lookupName; }) ([ target.name ] ++ target.aliases)
      ) declaredRepoTargetRecords;

      repoLookupNames = map (record: record.lookupName) repoLookupRecords;
      validLookupName = value: builtins.match "[A-Za-z0-9_.-]+" value != null;

      safeRelativeRepoPath =
        path:
        path != null
        && path != ""
        && !(lib.hasPrefix "/" path)
        && (
          path == "." || lib.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" path)
        );

      pathsOverlap =
        a: b:
        let
          left = lib.removeSuffix "/" a;
          right = lib.removeSuffix "/" b;
        in
        left == right || lib.hasPrefix "${left}/" right || lib.hasPrefix "${right}/" left;

      projectRepoPathRecords =
        name:
        map (repoName: {
          inherit repoName;
          path = (projectRepoTargets name projectItems.${name}).${repoName}.path;
        }) (lib.attrNames projectItems.${name}.repos);

      projectHasOverlappingRepoPaths =
        name:
        let
          records = projectRepoPathRecords name;
          pairs = lib.concatMap (
            a:
            map (b: [
              a
              b
            ]) records
          ) records;
        in
        lib.any (
          pair:
          (lib.elemAt pair 0).repoName != (lib.elemAt pair 1).repoName
          && pathsOverlap (lib.elemAt pair 0).path (lib.elemAt pair 1).path
        ) pairs;

      projectRecords = map (
        name:
        let
          project = projectItems.${name};
        in
        {
          inherit name;
          aliases = project.aliases;
          user = projectUser name project;
          home = projectHome name project;
          entryDir = projectEntryDir name project;
        }
      ) projectNames;

      repoTargetPathRecords = lib.concatMap (
        name:
        let
          project = projectItems.${name};
          workDir = projectWorkDir name project;
        in
        [
          {
            project = name;
            user = projectUser name project;
            home = projectHome name project;
            path = workDir;
          }
        ]
        ++ map (repoName: {
          project = name;
          user = projectUser name project;
          home = projectHome name project;
          path = (projectRepoTargets name project).${repoName}.path;
        }) (lib.attrNames (projectRepoTargets name project))
      ) projectNames;

      scopeActRecords = lib.concatMap (
        scopeName:
        let
          scopeProject = projectItems.${scopeName};
          scopeUser = projectUser scopeName scopeProject;
        in
        map (targetName: { inherit scopeUser targetName; }) (scopeIncludedProjects scopeName)
      ) (lib.filter (name: projectItems.${name}.scope.enable) projectNames);
    in
    {
      inherit
        catalogItems
        projectItems
        projectNames
        projectLookupNames
        projectUsers
        projectUser
        projectHome
        projectWorkDir
        projectHasPrefix
        scopeIncludedProjects
        repoPath
        declaredRepoTargets
        compatRepoTarget
        projectRepoTargets
        projectDefaultTarget
        projectEntryDir
        enrichedProjectItems
        declaredRepoTargetRecords
        repoLookupRecords
        repoLookupNames
        validLookupName
        safeRelativeRepoPath
        pathsOverlap
        projectRepoPathRecords
        projectHasOverlappingRepoPaths
        projectRecords
        repoTargetPathRecords
        scopeActRecords
        userPrefix
        workDirName
        ;
    };

  mkProjectAssertions =
    {
      model,
      optionPrefix ? "project",
      maxUserLength ? 31,
    }:
    let
      inherit (model)
        projectItems
        projectNames
        projectLookupNames
        projectUsers
        repoLookupNames
        validLookupName
        safeRelativeRepoPath
        projectHasOverlappingRepoPaths
        ;
    in
    [
      {
        assertion = lib.all (name: validLookupName name) projectNames;
        message = "${optionPrefix}.items keys must contain only letters, digits, dots, underscores, and dashes.";
      }
      {
        assertion = lib.all (name: lib.all validLookupName projectItems.${name}.aliases) projectNames;
        message = "${optionPrefix}.items aliases must contain only letters, digits, dots, underscores, and dashes.";
      }
      {
        assertion = lib.length (lib.unique projectLookupNames) == lib.length projectLookupNames;
        message = "${optionPrefix}.items keys and aliases must be unique.";
      }
      {
        assertion = lib.all (user: builtins.stringLength user <= maxUserLength) projectUsers;
        message = "${optionPrefix} generated user and group names must be at most ${toString maxUserLength} characters.";
      }
      {
        assertion = lib.length (lib.unique projectUsers) == lib.length projectUsers;
        message = "${optionPrefix} effective project users must be unique; shared project users need a reviewed alias-project design.";
      }
      {
        assertion = lib.all (name: !projectItems.${name}.hasReposAndCheckouts) projectNames;
        message = "${optionPrefix} items must not set both repos and checkouts.";
      }
      {
        assertion = lib.all (
          name:
          lib.all validLookupName (lib.attrNames projectItems.${name}.repos)
          && lib.all (repoName: lib.all validLookupName projectItems.${name}.repos.${repoName}.aliases) (
            lib.attrNames projectItems.${name}.repos
          )
        ) projectNames;
        message = "${optionPrefix} repo names and aliases must contain only letters, digits, dots, underscores, and dashes.";
      }
      {
        assertion = lib.all (
          name:
          lib.all (
            repoName:
            let
              repo = projectItems.${name}.repos.${repoName};
              names = [ repoName ] ++ repo.aliases;
            in
            lib.length (lib.unique names) == lib.length names
          ) (lib.attrNames projectItems.${name}.repos)
        ) projectNames;
        message = "${optionPrefix} repo aliases must be unique within each repo and must not duplicate the repo name.";
      }
      {
        assertion = lib.length (lib.unique repoLookupNames) == lib.length repoLookupNames;
        message = "${optionPrefix} declared repo names and aliases must be globally unique.";
      }
      {
        assertion = lib.intersectLists projectLookupNames repoLookupNames == [ ];
        message = "${optionPrefix} declared repo names and aliases must not collide with project names or aliases.";
      }
      {
        assertion = lib.all (
          name:
          projectItems.${name}.defaultRepo == null
          || lib.hasAttr projectItems.${name}.defaultRepo projectItems.${name}.repos
        ) projectNames;
        message = "${optionPrefix} defaultRepo must reference a declared repo in the same project.";
      }
      {
        assertion = lib.all (
          name:
          lib.length (
            lib.filter (repoName: projectItems.${name}.repos.${repoName}.primary) (
              lib.attrNames projectItems.${name}.repos
            )
          ) <= 1
        ) projectNames;
        message = "${optionPrefix} may declare at most one primary repo per project.";
      }
      {
        assertion = lib.all (
          name:
          lib.all (repoName: safeRelativeRepoPath projectItems.${name}.repos.${repoName}.path) (
            lib.attrNames projectItems.${name}.repos
          )
        ) projectNames;
        message = "${optionPrefix} repo paths must be '.' or safe relative paths with no empty, '.', or '..' components; absolute repo paths are not allowed in this patch.";
      }
      {
        assertion = lib.all (name: !projectHasOverlappingRepoPaths name) projectNames;
        message = "${optionPrefix} declared repo paths must be distinct and must not be ancestors or descendants of each other within a project.";
      }
      {
        assertion = lib.all (
          name: lib.all (included: lib.elem included projectNames) projectItems.${name}.scope.include
        ) projectNames;
        message = "${optionPrefix} scope.include entries must reference known project names.";
      }
    ];
in
{
  inherit
    loadProjectCatalog
    mkProjectModel
    mkProjectAssertions
    ;
}
