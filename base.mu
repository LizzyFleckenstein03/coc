inductive false |;

def not := fun (T : type) => T -> false;

inductive true |
    (mktrue : true);

inductive eq (T : type) (x : T) > (y : T) |
    (eq_refl : eq T x x);

def neq := fun (T : type) (x y : T) => not (eq T x y);

def eq_sym := fun (T : type) (x y : T) =>
        ind eq T x (fun (y : T) (_ : eq T x y) => eq T y x) (eq_refl T x) y
    : forall (T : type) (x y : T), eq T x y -> eq T y x;

def eq_trans := fun (T : type) (x y z : T) (eq_x_y : eq T x y) (eq_y_z : eq T y z) =>
        ind eq T y (fun (x : T) (_ : eq T y x) => eq T x z) eq_y_z x
            (eq_sym T x y eq_x_y)
    : forall (T : type) (x y z : T), eq T x y -> eq T y z -> eq T x z;

def eq_ext := fun (A B : type) (f : A -> B) (x y : A) (e : eq A x y) =>
        ind eq A x (fun (y : A) (e : eq A x y) => eq B (f x) (f y)) (eq_refl B (f x)) y e
    : forall (A B : type) (f : A -> B) (x y : A), eq A x y -> eq B (f x) (f y);

inductive bool |
    (btrue : bool)
    (bfalse : bool);

def if := fun (b : bool) (T : type) (t f : T) => elim bool T t f b;
def bnot := fun b : bool => if b bool bfalse btrue;
def band := fun a b : bool => if a bool b bfalse;
def bor := fun a b : bool => if a bool btrue b;
def beq := fun a b : bool => if a bool b (bnot b);

inductive option (T : type) |
    (none : option T)
    (some : T -> option T);

def map := fun (A B : type) (f : A -> B) => elim option A (option B) (none B) (fun (a : A) => some B (f a));
def flat_map := fun (A B : type) (f : A -> option B) => elim option A (option B) (none B) f;

inductive or (A B : type) |
    (or_left : A -> or A B)
    (or_right : B -> or A B);

def or_is_left := fun A B : type => elim or A B type (fun a : A => true) (fun b : B => false);
def or_is_right := fun A B : type => elim or A B type (fun a : A => false) (fun b : B => true);

def or_not_both := fun A B : type => ind or A B
        (fun o : or A B => or_is_left A B o -> not (or_is_right A B o))
        (fun (_ : A) (_ : true) (f : false) => f) (fun (_ : B) (f : false) (_ : true) => f)
    : forall (A B : type) (o : or A B), or_is_left A B o -> not (or_is_right A B o);

record and (A B : type) | mkand
    (fst : A)
    (snd : B);

record ex (T : type) (P : T -> type) | mkex
    (ex_var : T)
    (ex_prop : P ex_var);

inductive nat |
    (Z : nat)
    (S : nat -> nat);

notation display uint Z S;
notation parse uint Z S;

def is_zero := elim nat bool btrue (fun n : nat => bfalse);
def pred := elim nat (option nat) (none nat) (some nat);

def add := fun (a b : nat) => rec nat nat b (fun (n : nat) (r : nat) => S r) a;
def sub := fun (a b : nat) => rec nat (option nat) (some nat a) (fun n : nat => flat_map nat nat pred) b;

def nat_eqb := fun (a b : nat) => elim option nat bool bfalse is_zero (sub a b);

inductive le (n : nat) > (m : nat) |
    (le_n : le n n)
    (le_S : forall m : nat, le n m -> le n (S m));

def lt := fun n m : nat => le (S n) m;

inductive even > (n : nat) |
    (even_0 : even 0)
    (even_S : forall (n : nat), even n -> even (S (S n)));

inductive odd > (n : nat) |
    (odd_1 : odd 1)
    (odd_S : forall (n : nat), odd n -> odd (S (S n)));

record fin (n : nat) | mkfin
    (fin_n : nat)
    (fin_lt : lt fin_n n);

inductive list (T : type) |
    (nil : list T)
    (cons : T -> list T -> list T);

notation display array nil cons;
notation parse array nil cons;

def head := fun (T : type) => elim list T (option T) (none T) (fun (h : T) (t : list T) => some T h);
def tail := fun (T : type) => elim list T (list T) (nil T) (fun (h : T) (t : list T) => t);
def len := fun (T : type) => rec list T nat 0 (fun (h : T) (t : list T) (r : nat) => S r);

def app := fun (T : type) (a b : list T) => rec list T (list T) b (fun (h : T) (t : list T) (r : list T) => cons T h r) a;
