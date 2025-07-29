# Test Assertions

Quokka rewrites test assertions to use the more idiomatic `assert` and `refute` macros where semantically appropriate.

## Transformations

### `assert not` → `refute`

Rewrites negated assertions to use the `refute` macro:

```elixir
# Before
assert not user.status == :active
assert not Process.alive?(pid)

# After
refute user.status == :active
refute Process.alive?(pid)
```

### `assert !` → `refute`

Rewrites bang-negated assertions to use the `refute` macro:

```elixir
# Before
assert !user.active
assert !valid?
assert !result

# After
refute user.active
refute valid?
refute result
```

### `refute not` → `assert`

Rewrites negated refutations to use the `assert` macro:

```elixir
# Before
refute not user.status == :active
refute not Process.alive?(pid)

# After
assert user.status == :active
assert Process.alive?(pid)
```

### `refute !` → `assert`

Rewrites bang-negated refutations to use the `assert` macro:

```elixir
# Before
refute !user.active
refute !valid?
refute !result

# After
assert user.active
assert valid?
assert result
```

## Membership Testing

A common pattern in tests is checking that elements are not in collections:

```elixir
# Before
assert elem not in my_list
assert not (user in banned_users)
assert !(key in forbidden_keys)

# After
refute elem in my_list
refute user in banned_users
refute key in forbidden_keys
```