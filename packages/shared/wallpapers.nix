{
  # many wallpapers (per movie) by ghibli at: https://www.ghibli.jp/works/
  wallpaper1 = builtins.fetchurl {
    # many wallpapers (per movie) by ghibli at: https://www.ghibli.jp/works/
    url = "https://www.ghibli.jp/gallery/marnie047.jpg";
    sha256 = "1kpp6g436x119lkkx99v1xqn4gkv31gnsgn3grgnf9pqdsbv8x6m";
  };
  wallpaper2 = builtins.fetchurl {
    url = "https://www.ghibli.jp/gallery/marnie009.jpg";
    sha256 = "177n6nfy9la5g1h1hdm6lmcsq587lk108zcl1zgigcnshlccki9d";
  };
  wallpaper3 = "${./my_neighbour_totoro_sunset.png}";
}
