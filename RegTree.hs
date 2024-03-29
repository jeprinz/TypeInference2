module RegTree(
    RegTree(Mu, Var),
    intersect,
    replace,
    typeToString,
    typesToStrings,
    freeVars,
    Substitutions,
    applySubs,
    Id(Id, Idx)
)where

import Data.Set as Set
-- import Data.BiMap as BiMap
import Data.Map as Map
import Control.Monad.State
import NameGiver

data Id = Id Int | Idx Id Id deriving (Show, Eq, Ord)
data RegTree = Mu Id RegTree RegTree | Var Id deriving (Show)

replace :: RegTree -> Id -> RegTree -> RegTree -- replace t v x = t[x/v]
replace (Mu v t1 t2) var x = Mu v (replace t1 var x) (replace t2 var x)
replace (Var v) var x = if v == var then x else Var v

left :: RegTree -> RegTree
left (Mu topVar t1 t2) = case t1 of
                         (Var v) -> if v == topVar then Mu topVar t1 t2 else Var v
                         (Mu leftVar _ _ ) -> replace t1 topVar oldTree where
                                              oldTree = Mu topVar (Var leftVar) t2

right :: RegTree -> RegTree
right (Mu topVar t1 t2) = left (Mu topVar t2 t1)

name :: RegTree -> Id
name (Var v) = v
name (Mu v _ _) = v

type Substitutions = [(Id, RegTree)]

intersectI :: Set Id -> RegTree -> RegTree -> (RegTree, Substitutions)
intersectI b t1 t2 = let x = name t1
                         y = name t2
                     in if Set.member (Idx x y) b then (Var (Idx x y), [])
                        else case (t1, t2) of
                             ((Mu _ _ _), (Mu _ _ _)) -> (Mu (Idx x y) leftSide rightSide, subs) where
                                 b' = Set.insert (Idx x y) b
                                 (leftSide', subs1) = intersectI b' (left t1) (left t2)
                                 t1right = applySubs subs1 (right t1)
                                 t2right = applySubs subs1 (right t2)
                                 -- t1right = (right t1)
                                 -- t2right = (right t2)
                                 (rightSide', subs2) = intersectI b' t1right t2right
                                 subs = subs1 ++ subs2
                                 leftSide = applySubs subs leftSide'
                                 rightSide = applySubs subs rightSide'
                             ((Mu x _ _), (Var y)) -> (t1', [(y, t1')]) where
                                 t1' = replace t1 y (Var x)
                             ((Var x), (Mu y _ _)) -> (t2', [(x, t2')]) where
                                 t2' = replace t2 x (Var y)
                             ((Var x), (Var y)) -> (t1, [(y, t1)])

applySubs :: Substitutions -> RegTree -> RegTree
applySubs [] t = t
applySubs ((i, v) : ss) t = replace (applySubs ss t) i v

intersect :: RegTree -> RegTree -> (RegTree, Substitutions)
intersect t1 t2 = let (t, subs) = intersectI Set.empty t1 t2 in
                      ((applySubs subs t), subs)

freeVarsI :: RegTree -> Set Id -> Set Id
freeVarsI (Var v) bound = if Set.member v bound then Set.empty else Set.singleton v
freeVarsI (Mu v t1 t2) bound = Set.union (freeVarsI t1 bound') (freeVarsI t2 bound') where
    bound' = Set.insert v bound

freeVars :: RegTree -> Set Id
freeVars t = freeVarsI t Set.empty

example = Mu (Id 0) (Var (Id 0)) (Var (Id 0))
-- (A -> A) -> (B -> C)
example2 = Mu (Id 0) (Mu (Id 1) (Var (Id 2)) (Var (Id 2))) (Mu (Id 3) (Var (Id 4)) (Var (Id 5)))
-- u A . (B -> A) -> A -- left is u X . B -> (u A . X -> A)
example3 = Mu (Id 0) (Mu (Id 1) (Var (Id 2)) (Var (Id 0))) (Var (Id 0))

example4 = Mu (Id 0) (Mu (Id 1) (Var (Id 3)) (Var (Id 3))) (Mu (Id 2) (Var (Id 4)) (Var (Id 5)))
example5 = Mu (Id 10) (Mu (Id 11) (Var (Id 13)) (Var (Id 14))) (Mu (Id 12) (Var (Id 15)) (Var (Id 16)))
example6 = (Mu (Id 0) (Var (Id 1)) (Var (Id 1)))
example7 = Mu (Id 10) (Var (Id 11)) (Mu (Id 12) (Var (Id 11)) (Var (Id 11)))
example7' = Mu (Id 10) (Var (Id 1)) (Mu (Id 11) (Var (Id 1)) (Var (Id 1)))
example8 = Mu (Id 10) (Mu (Id 11) (Var (Id 1)) (Var (Id 1))) (Mu (Id 12) (Var (Id 1)) (Var (Id 1)))

example9 = Mu (Id 100) (Mu (Id 101) (Var (Id 1)) (Var (Id 2))) (Mu (Id 102) (Var (Id 1)) (Var (Id 3)))


-- everthing below here is for converting types to strings
type TypeState' = TypeState Id Char

typeToStringI :: RegTree -> Bool -> TypeState' String
typeToStringI (Mu v t1 t2) parens = do
    prefix <- if Set.member v (freeVars t1) || Set.member v (freeVars t2)
                 then do var <- getName v
                         -- return ("μ" ++ [var] ++ ".")
                         return ("u" ++ [var] ++ ".")
    else return ""
    s1 <- typeToStringI t1 True
    s2 <- typeToStringI t2 False
    return (if parens then ("(" ++ prefix ++ s1 ++ "->" ++ s2 ++ ")")
                      else (prefix ++ s1 ++ "->" ++ s2))


typeToStringI (Var v) _ = do name <- getName v
                             return [name]

typeToString :: RegTree -> String
typeToString t = evalState (typeToStringI t False) (['A'..'Z'], Map.empty)

typesToStringsI :: [RegTree] -> TypeState' [String]
typesToStringsI (t:ts) =
    do s <- typeToStringI t False
       rest <- typesToStringsI ts
       return (s : rest)

typesToStrings :: [RegTree] -> [String]
typesToStrings ts = evalState (typesToStringsI ts) (['A'..'Z'], Map.empty)
