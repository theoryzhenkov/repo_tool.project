{
  projectRecords = [
    {
      name = "alpha";
      aliases = [ "a" ];
      user = "usr.prj_alpha";
      home = "/tmp/project-alpha-home";
      entryDir = "/tmp/project-alpha-home/src";
    }
    {
      name = "beta";
      aliases = [ ];
      user = "usr.prj_beta";
      home = "/tmp/project-beta-home";
      entryDir = "/tmp/project-beta-home/src";
    }
  ];
  repoLookupRecords = [
    {
      lookupName = "repo.alpha";
      project = "alpha";
      name = "repo.alpha";
      ownerUser = "usr.prj_alpha";
      home = "/tmp/project-alpha-home";
      path = "/tmp/project-alpha-home/src";
    }
    {
      lookupName = "alpha-repo";
      project = "alpha";
      name = "repo.alpha";
      ownerUser = "usr.prj_alpha";
      home = "/tmp/project-alpha-home";
      path = "/tmp/project-alpha-home/src";
    }
  ];
  declaredRepoTargetRecords = [
    {
      project = "alpha";
      name = "repo.alpha";
      aliases = [ "alpha-repo" ];
      ownerUser = "usr.prj_alpha";
      home = "/tmp/project-alpha-home";
      path = "/tmp/project-alpha-home/src";
    }
  ];
  repoTargetPathRecords = [
    {
      project = "alpha";
      user = "usr.prj_alpha";
      home = "/tmp/project-alpha-home";
      path = "/tmp/project-alpha-home/src";
    }
    {
      project = "beta";
      user = "usr.prj_beta";
      home = "/tmp/project-beta-home";
      path = "/tmp/project-beta-home/src";
    }
  ];
  scopeActRecords = [
    {
      scopeUser = "usr.prj_alpha";
      targetName = "beta";
    }
  ];
}
