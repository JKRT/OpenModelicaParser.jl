"""
Tests of the MetaModelica grammar: uniontypes, match and matchcontinue expressions, patterns, lists, try. The trees are
read through their fields (`isa` and field access), so the tests need no MetaModelica.
"""
module MetaModelicaTests

using Test
import OpenModelicaParser
import OpenModelicaParser.Absyn
import ImmutableList: SOME

"""Parse MetaModelica source: `acceptedGram` 2 selects MetaModelica, `languageStandard` 9999 is experimental."""
function mmParse(code::String)::Absyn.Program
  return OpenModelicaParser.parseString(code, "<test>", 2, 9999)
end

"""The first class of a parsed program."""
function firstClass(prog::Absyn.Program)::Absyn.CLASS
  return first(collect(prog.classes))::Absyn.CLASS
end

"""The class parts of the first class (its body is `PARTS`)."""
function firstClassParts(prog::Absyn.Program)::Vector{Absyn.ClassPart}
  return collect((firstClass(prog).body::Absyn.PARTS).classParts)
end

"""The statements of the first class's algorithm section."""
function algorithmItems(prog::Absyn.Program)::Vector{Absyn.AlgorithmItem}
  local sections::Vector{Absyn.ClassPart} = filter(p -> p isa Absyn.ALGORITHMS, firstClassParts(prog))
  @test length(sections) == 1
  return collect((first(sections)::Absyn.ALGORITHMS).contents)
end

"""The right-hand side of the first assignment in the first class's algorithm section."""
function firstAssignedValue(prog::Absyn.Program)::Absyn.Exp
  local alg::Absyn.Algorithm = first(algorithmItems(prog)).algorithm_
  @test alg isa Absyn.ALG_ASSIGN
  return (alg::Absyn.ALG_ASSIGN).value
end

"""The cases of the match expression assigned first in the first class's algorithm section."""
function matchCases(prog::Absyn.Program)::Vector{Absyn.Case}
  local exp::Absyn.Exp = firstAssignedValue(prog)
  @test exp isa Absyn.MATCHEXP
  return collect((exp::Absyn.MATCHEXP).cases)
end

"""True for `CREF(CREF_IDENT(name, _))`."""
isIdentCref(exp::Absyn.Exp, name::String)::Bool =
  exp isa Absyn.CREF && exp.componentRef isa Absyn.CREF_IDENT && exp.componentRef.name == name

"""True for `CREF(WILD())`, the wildcard `_`."""
isWild(exp::Absyn.Exp)::Bool = exp isa Absyn.CREF && exp.componentRef isa Absyn.WILD

"""True for an integer literal of the given value."""
isInteger(exp::Absyn.Exp, value::Int)::Bool = exp isa Absyn.INTEGER && exp.value == value

@testset "MetaModelica: Uniontype" begin
  local prog::Absyn.Program = mmParse("""
    uniontype MyOption
      record SOME
        Real value;
      end SOME;
      record NONE
      end NONE;
    end MyOption;
  """)
  local cls::Absyn.CLASS = firstClass(prog)
  @test cls.name == "MyOption"
  @test cls.restriction isa Absyn.R_UNIONTYPE
  local parts::Vector{Absyn.ClassPart} = firstClassParts(prog)
  @test first(parts) isa Absyn.PUBLIC
  local contents::Vector{Absyn.ElementItem} = collect((first(parts)::Absyn.PUBLIC).contents)
  @test length(contents) == 2
  for (item, name) in zip(contents, ("SOME", "NONE"))
    @test item isa Absyn.ELEMENTITEM
    local spec::Absyn.ElementSpec = (item::Absyn.ELEMENTITEM).element.specification
    @test spec isa Absyn.CLASSDEF
    @test spec.class_.name == name
    @test spec.class_.restriction isa Absyn.R_RECORD
  end
end

@testset "MetaModelica: Match expression" begin
  local prog::Absyn.Program = mmParse("""
    function testMatch
      input Integer x;
      output Integer y;
    algorithm
      y := match x
        case 1 then 10;
        case 2 then 20;
        else 0;
      end match;
    end testMatch;
  """)
  local cls::Absyn.CLASS = firstClass(prog)
  @test cls.name == "testMatch"
  @test cls.restriction isa Absyn.R_FUNCTION
  @test cls.restriction.functionRestriction isa Absyn.FR_NORMAL_FUNCTION
  @test cls.restriction.functionRestriction.purity isa Absyn.NO_PURITY
  @test (firstAssignedValue(prog)::Absyn.MATCHEXP).matchTy isa Absyn.MATCH
  local cases::Vector{Absyn.Case} = matchCases(prog)
  @test length(cases) == 3
  @test cases[1] isa Absyn.CASE && isInteger(cases[1].pattern, 1) && isInteger(cases[1].result, 10)
  @test cases[2] isa Absyn.CASE && isInteger(cases[2].pattern, 2) && isInteger(cases[2].result, 20)
  @test cases[3] isa Absyn.ELSE && isInteger(cases[3].result, 0)
end

@testset "MetaModelica: Matchcontinue expression" begin
  local prog::Absyn.Program = mmParse("""
    function testMC
      input Integer x;
      output Integer y;
    algorithm
      y := matchcontinue x
        case 1 then 42;
        else 0;
      end matchcontinue;
    end testMC;
  """)
  @test (firstAssignedValue(prog)::Absyn.MATCHEXP).matchTy isa Absyn.MATCHCONTINUE
  local cases::Vector{Absyn.Case} = matchCases(prog)
  @test length(cases) == 2
  @test cases[1] isa Absyn.CASE
  @test cases[2] isa Absyn.ELSE
end

@testset "MetaModelica: List cons operator (::)" begin
  local prog::Absyn.Program = mmParse("""
    function testCons
      input Integer h;
      input list<Integer> t;
      output list<Integer> result;
    algorithm
      result := h :: t;
    end testCons;
  """)
  local exp::Absyn.Exp = firstAssignedValue(prog)
  @test exp isa Absyn.CONS
  @test isIdentCref(exp.head, "h")
  @test isIdentCref(exp.rest, "t")
end

@testset "MetaModelica: Empty list {}" begin
  local prog::Absyn.Program = mmParse("""
    function testEmpty
      output list<Integer> result;
    algorithm
      result := {};
    end testEmpty;
  """)
  local exp::Absyn.Exp = firstAssignedValue(prog)
  #= Empty {} parses as ARRAY with an empty list =#
  @test exp isa Absyn.ARRAY
  @test isempty(exp.arrayExp)
end

@testset "MetaModelica: Wildcard pattern (_)" begin
  local prog::Absyn.Program = mmParse("""
    function testWild
      input Integer x;
      output Integer y;
    algorithm
      y := match x
        case _ then 99;
      end match;
    end testWild;
  """)
  local cases::Vector{Absyn.Case} = matchCases(prog)
  @test length(cases) == 1
  @test cases[1] isa Absyn.CASE
  @test isInteger(cases[1].result, 99)
  #= The wildcard _ parses as CREF(WILD()) =#
  @test isWild(cases[1].pattern)
end

@testset "MetaModelica: As-pattern binding" begin
  local prog::Absyn.Program = mmParse("""
    function testAs
      input list<Integer> lst;
      output Integer h;
      output list<Integer> all;
    algorithm
      (h, all) := match lst
        case all as h :: _ then (h, all);
      end match;
    end testAs;
  """)
  local cases::Vector{Absyn.Case} = matchCases(prog)
  @test cases[1] isa Absyn.CASE
  #= AS("all", CONS(CREF("h"), CREF(WILD()))) =#
  local pattern::Absyn.Exp = cases[1].pattern
  @test pattern isa Absyn.AS
  @test pattern.id == "all"
  @test pattern.exp isa Absyn.CONS
  @test isIdentCref(pattern.exp.head, "h")
  @test isWild(pattern.exp.rest)
end

@testset "MetaModelica: Try-catch in algorithm" begin
  local prog::Absyn.Program = mmParse("""
    function testTry
      input Integer x;
      output Integer y;
    algorithm
      try
        y := x + 1;
      else
        y := 0;
      end try;
    end testTry;
  """)
  local alg::Absyn.Algorithm = first(algorithmItems(prog)).algorithm_
  @test alg isa Absyn.ALG_TRY
  #= Both branches have one assignment =#
  for body in (alg.body, alg.elseBody)
    local items::Vector{Absyn.AlgorithmItem} = collect(body)
    @test length(items) == 1
    @test first(items) isa Absyn.ALGORITHMITEM
    @test first(items).algorithm_ isa Absyn.ALG_ASSIGN
  end
end

@testset "MetaModelica: Match with local declarations" begin
  local prog::Absyn.Program = mmParse("""
    function testLocal
      input Integer x;
      output String s;
    algorithm
      s := match x
        local Integer tmp;
        case 1
          algorithm
            tmp := x + 1;
          then "one";
        else "other";
      end match;
    end testLocal;
  """)
  local exp::Absyn.Exp = firstAssignedValue(prog)
  @test exp isa Absyn.MATCHEXP
  @test exp.matchTy isa Absyn.MATCH
  @test !isempty(exp.localDecls)
  local cases::Vector{Absyn.Case} = matchCases(prog)
  @test length(cases) == 2
  @test cases[1] isa Absyn.CASE && isInteger(cases[1].pattern, 1)
  @test cases[1].result isa Absyn.STRING && cases[1].result.value == "one"
  @test cases[2] isa Absyn.ELSE
  @test cases[2].result isa Absyn.STRING && cases[2].result.value == "other"
end

@testset "MetaModelica: Match with guard condition" begin
  local prog::Absyn.Program = mmParse("""
    function testGuard
      input Integer x;
      output Integer y;
    algorithm
      y := match x
        case 1 guard x > 0 then 10;
        else 0;
      end match;
    end testGuard;
  """)
  local c1::Absyn.Case = first(matchCases(prog))
  @test c1 isa Absyn.CASE && isInteger(c1.pattern, 1) && isInteger(c1.result, 10)
  #= The guard is SOME(x > 0) =#
  @test c1.patternGuard isa SOME
  local guard::Absyn.Exp = c1.patternGuard.data
  @test guard isa Absyn.RELATION
  @test guard.op isa Absyn.GREATER
end

@testset "MetaModelica: Nested cons builds list" begin
  local prog::Absyn.Program = mmParse("""
    function testNestedCons
      output list<Integer> result;
    algorithm
      result := 1 :: 2 :: 3 :: {};
    end testNestedCons;
  """)
  #= CONS(1, CONS(2, CONS(3, ARRAY({})))) =#
  local exp::Absyn.Exp = firstAssignedValue(prog)
  for value in 1:3
    @test exp isa Absyn.CONS
    @test isInteger(exp.head, value)
    exp = exp.rest
  end
  @test exp isa Absyn.ARRAY
  @test isempty(exp.arrayExp)
end

end
