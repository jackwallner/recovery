# Recharge Play assets

Prepared for later Play staging. No listing or product has been uploaded.

- `en-US/`: source listing copy, without prices.
- `metadata/android/en-US/`: matching API staging layout, with verified limits.
- `icon-512.png`: the existing app icon at 512 pixels.
- `feature-graphic.png`: 1024 x 500 graphic, with SVG source.
- `screenshots/`: real Pro captures of free screens with local workout fixtures.
  Native 720 x 1440 captures meet the 2:1 limit. PNG copies preserve the decoded
  JPEG pixels exactly for the staging tool; the JPEG originals are retained. They show only the free tier,
  with no purchase unlock or Test Store prices.
- `../docs/android/`: Android privacy policy and terms.
- `../scripts/play-products.py`: offline plan by default. Proposed US ladder:
  $4.79 monthly, $23.99 yearly and $47.99 lifetime, seven-day new-subscriber
  trials and fleet PPP adjustments. No Play requests without `--apply`.

Remaining: Play app creation, health permissions declarations, Data Safety and
App content forms, Play products and credentials, billing tests from Play,
listing staging, uploads and review submission.
