## 0.2.6 (unreleased)

- Improved performance
- Improved `inspect` method
- Fixed error with `fit` after loading

## 0.2.5 (2021-02-20)

- Added `top_items` method
- Added `optimize_similar_users` method
- Added support for Faiss for `optimize_item_recs` and `optimize_similar_users` methods
- Added `rmse` method
- Improved performance

## 0.2.4 (2021-02-15)

- Added `user_ids` and `item_ids` methods
- Added `user_id` argument to `user_factors`
- Added `item_id` argument to `item_factors`

## 0.2.3 (2020-11-28)

- Added `predict` method
- Fixed bad recommendations and scores with `user_recs` and explicit feedback
- Fixed `item_ids` option for `user_recs`

## 0.2.2 (n/a)

- Not available (released by previous gem owner)

## 0.2.1 (2020-10-28)

- Fixed issue with `user_recs` returning rated items

## 0.2.0 (2020-07-31)

- Changed score to always be between -1 and 1 for `item_recs` and `similar_users` (cosine similarity - this makes it easier to understand and consistent with `optimize_item_recs` and `optimize_similar_users`)

## 0.1.3 (2020-06-28)

- Added support for Rover
- Raise error when missing user or item ids
- Fixed string keys for Daru data frames
- `optimize_item_recs` and `optimize_similar_users` methods are no longer experimental

## 0.1.2 (2020-03-26)

- Added experimental `optimize_item_recs` and `optimize_similar_users` methods

## 0.1.1 (2019-11-14)

- Fixed Rails integration

## 0.1.0 (2019-11-14)

- First release
