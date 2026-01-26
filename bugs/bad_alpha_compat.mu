check fun (A : type) (A : type) (a : A) => a
    : forall (A : type) (A : type) (a : A), A;

# previous implementation had a bug that allowed this
check
    fun (A : type) (A : type) (a : A) => a
    : forall (A : type) (B : type) (a : A), A;
