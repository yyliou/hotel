# make-logo.R ---------------------------------------------------------------
# Reproducibly build the twhotel hex sticker the "tidyverse" way, using the
# hexSticker package (the same toolchain the tidyverse / rOpenSci community use).
#
#   install.packages(c("hexSticker", "ggplot2", "sysfonts", "showtext"))
#
# Run from the package root:  source("make-logo.R")
# It writes man/figures/logo.png (the file the README + pkgdown expect).
#
# NOTE: the shipped logo (man/figures/logo.png) was hand-drawn as SVG -- see
# man/figures/logo.svg and HEX-STICKER-GUIDE.md. This script reproduces an
# equivalent hexSticker version.
# ---------------------------------------------------------------------------

library(hexSticker)
library(ggplot2)
library(sysfonts)
library(showtext)

sysfonts::font_add_google("Nunito", "nunito")
showtext::showtext_auto()

# Subplot: a tiny "skyline" bar chart -- each bar is a hotel and a monthly stat,
# the metaphor of this package (per-hotel monthly operating statistics).
df <- data.frame(
  x = 1:6,
  h = c(1.5, 2.0, 1.7, 2.35, 1.85, 1.4),
  hi = c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE)  # tallest bar = accent
)

p <- ggplot(df, aes(x, h, fill = hi)) +
  geom_col(width = 0.7) +
  scale_fill_manual(values = c(`FALSE` = "#ffffff", `TRUE` = "#e0c2d2")) +
  theme_void() + theme_transparent() +
  theme(legend.position = "none")

# Plum palette, matching the yyliou hex series (flat fill, darker border, no
# gradient/url). NOTE: the shipped logo is the hand-drawn man/figures/logo.svg;
# this hexSticker version is only an approximation.
sticker(
  subplot   = p,
  s_x = 1, s_y = 0.92, s_width = 1.25, s_height = 0.85,

  package   = "twhotel",
  p_family  = "nunito", p_size = 22, p_y = 1.5, p_color = "#ffffff",

  h_fill    = "#7a4a63",   # plum body
  h_color   = "#5c3149",   # darker plum border
  h_size    = 1.4,

  url       = "",

  dpi       = 300,
  filename  = "man/figures/logo.png"
)

message("Wrote man/figures/logo.png")

# Wire it into the package + README in one line:
#   usethis::use_logo("man/figures/logo.png")
