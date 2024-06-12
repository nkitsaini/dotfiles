{ ... }: {
  users.users.root = {
    openssh.authorizedKeys.keys = import ../../packages/authorized_keys.nix;
    hashedPassword =
      "$6$DOMc34qNu.Di8xUo$N/GqsvZorJj.fPnpICIGyV0ncb62.c.iQncYA2Aww8GWEiIew6nmKwRx3E.IqtxLdt2JmxCqVTuRDULJPwBlD.";
  };
}
