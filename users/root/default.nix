{ ... }: {
  users.users.root = {
    openssh.authorizedKeys.keys = import ../../packages/authorized_keys.nix;
    hashedPassword =
      "$6$LQ07pSaH7PgyFkLu$5M1sHga9IQ4xqdvYuhzx1v5eKZf3s13v6Q8KrYlQJ3Pc0jCdeUOwFuGkzw1/4BHWGKxmkO3unSfjzzgg7uGqA/";
  };
}
