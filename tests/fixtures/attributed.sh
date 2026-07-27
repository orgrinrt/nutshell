#[pub]
marked_fn() { :; }

plain_fn() { :; }

#[pub]
# Some prose about the function, which sits between the attribute and the
# definition exactly as a doc comment does.
documented_fn() { :; }

#[allow(loc = 400)]
limited_fn() { :; }

#[pub(lib)]
internal_fn() { :; }

#[pub]
x=1
after_code_fn() { :; }

#[test]
a_test_fn() { :; }

#[test]
b_test_fn() { :; }
