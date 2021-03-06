LightRecord
===========

ActiveRecord extension to kick the speed of allocating ActiveRecord object

It provides minimalistic wrapper of ActiveRecord to select big data.

#### `scope.light_records`

```ruby
records = User.limit(1_000_000).light_records
records # => array of records. Very fast and very memory efficient
```

Idea is to skip all magic related to attributes and object initialization. This creates new class inherited from your model. That allows us to create only one extra object when we initialize new record.


Simply it become something like this:

```ruby
class User_light_record < User
  def initialize(attributes)
    @attributes = attributes
  end

  def email
    @attributes[:email]
  end
end
```
#### `scope.light_records_each`


Other method: `.light_records_each`, it will utilize `stream: true` feature from mysql2 client. So it will initialize objects one by one for every interation:

```ruby
User.limit(1_000_000).light_records_each do |user|
  user.do_something
end
```

This allow you to interate big amount of data without using `find_each` or `find_in_batches` because with `light_records_each` it will use very low memory. Or allow you to use `find_in_batches` with bigger batch size


#### Benchmarks

Still on a way,
but I try to use in some project and it gives 3-5 times improvement, and 2-3 times less memory usage


---

Sometimes this can break functionality because it will override attribute methods and disable some of features in activerecord.

```ruby
class User < ActiveRecord::Base
  # this module will be included in extending class when we use light_records and light_records_each
  module LightRecord
    def sometihng
    end
  end
end
```

Note: when you use LightRecord instances it will break type casting
