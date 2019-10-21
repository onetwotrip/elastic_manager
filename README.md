# elastic_manager

Manager for logstash indices in elasticsearch. Why? Because qurator sucks!

[![Build Status](https://travis-ci.org/onetwotrip/elastic_manager.svg?branch=master)](https://travis-ci.org/onetwotrip/elastic_manager)

Use ENV variables for run. Required variables:

- TASK
- INDICES
- FROM-TO or DAYSAGO (FROM-TO pair have precedence over DAYSAGO)

Progress:

- [x] Open closed indices
- [x] Open indices in snapshot (restore snapshot)
- [x] Open by date from and to
- [x] Open by daysago
- [x] Open all indices
- [x] Close indices
- [x] Chill indices
- [x] Delete indices
- [x] Snapshot indices
- [x] Delete snapshots
- [x] Override daysago for concrete index
- [x] Skip any task for specific index
- [ ] Skip index deleting when snapshot if configured

# NEW

test gem localy
ruby -Ilib bin/elastic_manager

dry run режим ?
удалять роли которых нет в конфиге ?
