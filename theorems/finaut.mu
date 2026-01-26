include base.mu;

record dfa (A : type) | mkdfa
    (nstates : nat)
    (start : fin nstates)
    (trans : fin nstates -> A -> fin nstates)
    (accept : fin nstates -> bool);

def states := fun (A : type) (d : dfa A) => fin (nstates A d);

def dfa_cont := fun (A : type) (d : dfa A) (q : states A d) => rec list A (states A d) q
    (fun (a : A) (_ : list A) (q : states A d) => trans A d q a);

def dfa_run := fun (A : type) (d : dfa A) => dfa_cont A d (start A d);
def dfa_accept := fun (A : type) (d : dfa A) (l : list A) => accept A d (dfa_run A d l);

def st0 := mkfin 2 0 (le_S 1 1 (le_n 1));
def st1 := mkfin 2 1 (le_n 2);

inductive alpha | (a : alpha) (b : alpha);

def simple := mkdfa alpha 2
        st0
        (fun (q : fin 2) => elim alpha (fin 2) q st1)
        (fun (q : fin 2) => nat_eqb (fin_n 2 q) 0)
    : dfa alpha;

eval dfa_accept alpha simple [a : alpha];
eval dfa_accept alpha simple [b : alpha];
eval dfa_accept alpha simple [a, a, a : alpha];
eval dfa_accept alpha simple [a, b, a : alpha];
eval dfa_accept alpha simple [: alpha];
