
"""
    struct AffineOperator{A<:AbstractMatrix,B<:AbstractVector} <: NonlinearOperator
      matrix::A
      vector::B
    end
"""
struct AffineOperator{A<:AbstractMatrix,B<:AbstractVector} <: NonlinearOperator
  matrix::A
  vector::B
end

"""
"""
get_matrix(op::AffineOperator) = op.matrix

"""
"""
get_vector(op::AffineOperator) = op.vector

function residual!(b::AbstractVector,op::AffineOperator,x::AbstractVector)
  mul!(b,op.matrix,x)
  b .-=  op.vector
  b
end

function jacobian!(A::AbstractMatrix,op::AffineOperator,x::AbstractVector)
  copy_entries!(A,op.matrix)
  A
end

function jacobian(op::AffineOperator,x::AbstractVector)
  op.matrix
end

function zero_initial_guess(::Type{T},op::AffineOperator) where T
  n = size(op.matrix,2)
  zeros(T,n)
end

function allocate_residual(op::AffineOperator,x::AbstractVector)
  similar(x,eltype(x),length(op.vector))
end

function allocate_jacobian(op::AffineOperator,x::AbstractVector)
  op.matrix
end

"""
    abstract type LinearSolver <: NonlinearSolver end

- [`symbolic_setup(::LinearSolver,mat::AbstractMatrix)`](@ref)
- [`test_linear_solver`](@ref)

"""
abstract type LinearSolver <: NonlinearSolver end

"""
    symbolic_setup(::LinearSolver,mat::AbstractMatrix) -> SymbolicSetup
"""
function symbolic_setup(::LinearSolver,mat::AbstractMatrix)
  @abstractmethod
end

"""
    solve(ls::LinearSolver,A::AbstractMatrix,b::AbstractVector)
"""
function solve(ls::LinearSolver,A::AbstractMatrix,b::AbstractVector)
  ss = symbolic_setup(ls,A)
  ns = numerical_setup(ss,A)
  x = similar(b)
  solve!(x,ns,b)
  x
end

"""
    abstract type SymbolicSetup <: GridapType end

- [`numerical_setup(::SymbolicSetup,mat::AbstractMatrix)`](@ref)
"""
abstract type SymbolicSetup <: GridapType end

"""
    numerical_setup(::SymbolicSetup,mat::AbstractMatrix) -> NumericalSetup
"""
function numerical_setup(::SymbolicSetup,mat::AbstractMatrix)
  @abstractmethod
end

"""
    abstract type NumericalSetup <: GridapType end

- [`numerical_setup!(::NumericalSetup,mat::AbstractMatrix)`](@ref)
- [`solve!(x::AbstractVector,::NumericalSetup,b::AbstractVector)`](@ref)
"""
abstract type NumericalSetup <: GridapType end

"""
    numerical_setup!(::NumericalSetup,mat::AbstractMatrix)
"""
function numerical_setup!(::NumericalSetup,mat::AbstractMatrix)
  @abstractmethod
end

"""
    solve!(x::AbstractVector,::NumericalSetup,b::AbstractVector)
"""
function solve!(x::AbstractVector,::NumericalSetup,b::AbstractVector)
  @abstractmethod
end

"""
    test_linear_solver(
      ls::LinearSolver,
      A::AbstractMatrix,
      b::AbstractVector,
      x::AbstractVector)
"""
function test_linear_solver(
  ls::LinearSolver,
  A::AbstractMatrix,
  b::AbstractVector,
  x::AbstractVector)

  y = solve(ls,A,b)
  @test x ≈ y

  ss = symbolic_setup(ls,A)
  ns = numerical_setup(ss,A)
  numerical_setup!(ns,A)
  solve!(y,ns,b)
  @test x ≈ y

  op = AffineOperator(A,b)
  x0 = copy(x)
  test_nonlinear_solver(ls,op,x0,x)

end

# Implementation of NonlinearSolver interface
# A LinearSolver is only able to solve an AffineOperator

function solve!(x::AbstractVector,ls::LinearSolver,op::NonlinearOperator)
  @unreachable "A LinearSolver can only solve an AffineOperator"
end

function solve!(x::AbstractVector,ls::LinearSolver,op::NonlinearOperator,cache)
  @unreachable "A LinearSolver can only solve an AffineOperator"
end

function solve!(x::AbstractVector,ls::LinearSolver,op::AffineOperator)
  A = op.matrix
  b = op.vector
  ss = symbolic_setup(ls,A)
  ns = numerical_setup(ss,A)
  solve!(x,ns,b)
  ns
end

function solve!(x::AbstractVector,ls::LinearSolver,op::AffineOperator,cache)
  newmatrix = true
  solve!(x,ls,op,cache,newmatrix)
end

"""
    solve!(
      x::AbstractVector,
      ls::LinearSolver,
      op::AffineOperator,
      cache,
      newmatrix::Bool)
"""
function solve!(
  x::AbstractVector,ls::LinearSolver,op::AffineOperator,cache,newmatrix::Bool)
  A = op.matrix
  b = op.vector
  ns = cache
  if newmatrix
    numerical_setup!(ns,A)
  end
  solve!(x,ns,b)
  x
end

# Concrete implementations

"""
    struct LUSolver <: LinearSolver end

Wrapper of the LU solver available in julia
"""
struct LUSolver <: LinearSolver end

struct LUSymbolicSetup <: SymbolicSetup end

mutable struct LUNumericalSetup{F} <: NumericalSetup
  factors::F
end

symbolic_setup(::LUSolver,mat::AbstractMatrix) = LUSymbolicSetup()

numerical_setup(::LUSymbolicSetup,mat::AbstractMatrix) = LUNumericalSetup(lu(mat))

function numerical_setup!(ns::LUNumericalSetup, mat::AbstractMatrix)
  fac = lu(mat)
  ns.factors = fac
end

function solve!(
  x::AbstractVector,ns::LUNumericalSetup,b::AbstractVector)
  y = ns.factors\b # the allocation of y can be avoided
  x .= y
end

"""
    struct BackslashSolver <: LinearSolver end

Wrapper of the backslash solver available in julia
This is typically faster than LU for a single solve
"""
struct BackslashSolver <: LinearSolver end

struct BackslashSymbolicSetup <: SymbolicSetup end

mutable struct BackslashNumericalSetup{T<:AbstractMatrix} <: NumericalSetup
  A::T
end

symbolic_setup(::BackslashSolver,mat::AbstractMatrix) = BackslashSymbolicSetup()

numerical_setup(::BackslashSymbolicSetup,mat::AbstractMatrix) = BackslashNumericalSetup(mat)

function numerical_setup!(ns::BackslashNumericalSetup, mat::AbstractMatrix)
  ns.A = mat
end

function solve!(
  x::AbstractVector,ns::BackslashNumericalSetup,b::AbstractVector)
   copyto!(x, ns.A\b)
end