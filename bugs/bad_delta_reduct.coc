def T : type;

def a : T;
def b : T;
def c := a;

# past bug: this should yield a, but it yields b
eval ((fun x : T -> T => x) (fun (a : T) => c)) b;
