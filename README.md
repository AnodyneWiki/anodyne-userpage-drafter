# log-pref

### Dependencies
- ruby
- ruby-httparty

### Usage

#### CSV Log format
```csv
timestamp,user,med,amount,ROA,comment
2025-12-03T08:00:31.987Z,User,Metaphedrone,50mg,Intravenous,left-median-cubital hydrochloride-salt
```

```shell
ruby log-pref.rb --csv logs.csv -p preferences.json
```

#### Journal exported logs
```shell
ruby dkinplot.rb --journal journal_export.json -p preferences.json
```
