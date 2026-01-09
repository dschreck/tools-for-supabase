# Supabase Tools

> "I have to have my tools!"
>
> \- Dennis Reynolds, _It's Always Sunny in Philadelphia_
>
> <http://youtube.com/watch?v=gWGTehbT2LQ>


Collection of some tools I use for Supabase projcets.

## `lint-templates.sh`

- Checks the template files you have to ensure you dont have a bad variable, as supabase really doesn't tell you much about why it fails

### Tests

```bash
just test
just test "invalid variable"
just lint --no-emoji --file example/templates/confirmation.html
```

## About

