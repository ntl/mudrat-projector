# MudratProjector

Simple financial projection built in ruby.

```ruby
include MudratProjector

projector = Projector.new from: "1/1/2000"
projector.add_account :checking, type: :asset
projector.add_account :uncle_vinnie, type: :revenue
projector.add_transaction(
  date: "7/4/2000",
  debit:  { amount: 6000, account_id: :checking },
  credit: { amount: 6000, account_id: :uncle_vinnie }
)
projector.project to: "12/31/2000"
assert_equal 5000, projector.account_balance(:checking)
```

## Installation

Add this line to your application's Gemfile:

    gem 'mudrat_projector'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install mudrat_projector

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
