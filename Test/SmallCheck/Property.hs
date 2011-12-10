module Test.SmallCheck.Property (
  TestCase(..),
  TestResult(..),
  resultIsOk,

  Property, Depth, Testable(..),
  property, mkProperty,
  forAll, forAllElem,
  exists, existsDeeperBy, thereExists, thereExistsElem,
  exists1, exists1DeeperBy, thereExists1, thereExists1Elem,
  (==>)
  ) where

import Test.SmallCheck.Series

data TestResult
    = Pass
    | Fail
    | Inappropriate
        -- ^ 'Inappropriate' means that the precondition of '==>'
        -- was not satisfied
data TestCase = TestCase { result :: TestResult, arguments :: [String] }

-- | Wrapper type for 'Testable's
newtype Property = Property (Depth -> [TestCase])

-- | Wrap a 'Testable' into a 'Property'
property :: Testable a => a -> Property
property = Property . test

-- | A lower-level way to create properties. Use 'property' if possible.
--
-- The argument is a function that produces the list of results given the depth
-- of testing.
mkProperty :: (Depth -> [TestCase]) -> Property
mkProperty = Property

-- | Anything of a 'Testable' type can be regarded as a \"test\"
class Testable a where
  test :: a -> Depth -> [TestCase]

instance Testable Bool where
  test b _ = [TestCase (boolToResult b) []]

instance (Serial a, Show a, Testable b) => Testable (a->b) where
  test f = f' where Property f' = forAll series f

instance Testable Property where
  test (Property f) d = f d

forAll :: (Show a, Testable b) => Series a -> (a->b) -> Property
forAll xs f = Property $ \d ->
  [ r{arguments = show x : arguments r}
  | x <- xs d, r <- test (f x) d ]

forAllElem :: (Show a, Testable b) => [a] -> (a->b) -> Property
forAllElem xs = forAll (const xs)

existence :: (Show a, Testable b) => Bool -> Series a -> (a->b) -> Property
existence u xs f = Property existenceDepth
  where
  existenceDepth d = [ TestCase (boolToResult valid) arguments ]
    where
    witnesses = [ show x | x <- xs d, all (resultIsOk . result) (test (f x) d) ]
    valid     = enough witnesses
    enough    = if u then unique else (not . null)
    arguments = if valid then []
                else if null witnesses then ["non-existence"]
                else "non-uniqueness" : take 2 witnesses

unique :: [a] -> Bool
unique [_] = True
unique  _  = False

resultIsOk :: TestResult -> Bool
resultIsOk r =
    case r of
        Fail -> False
        Pass -> True
        Inappropriate -> True

boolToResult :: Bool -> TestResult
boolToResult b = if b then Pass else Fail

thereExists :: (Show a, Testable b) => Series a -> (a->b) -> Property
thereExists = existence False

thereExists1 :: (Show a, Testable b) => Series a -> (a->b) -> Property
thereExists1 = existence True

thereExistsElem :: (Show a, Testable b) => [a] -> (a->b) -> Property
thereExistsElem xs = thereExists (const xs)

thereExists1Elem :: (Show a, Testable b) => [a] -> (a->b) -> Property
thereExists1Elem xs = thereExists1 (const xs)

-- | @'exists' p@ holds iff it is possible to find an argument @a@ (within the
-- depth constraints!) satisfying the predicate @p@
exists :: (Show a, Serial a, Testable b) => (a->b) -> Property
exists = thereExists series

-- | Like 'exists', but additionally require the uniqueness of the
-- argument satisfying the predicate
exists1 :: (Show a, Serial a, Testable b) => (a->b) -> Property
exists1 = thereExists1 series

-- | The default testing of existentials is bounded by the same depth as their
-- context. This rule has important consequences. Just as a universal property
-- may be satisfied when the depth bound is shallow but fail when it is deeper,
-- so the reverse may be true for an existential property. So when testing
-- properties involving existentials it may be appropriate to try deeper testing
-- after a shallow failure. However, sometimes the default same-depth-bound
-- interpretation of existential properties can make testing of a valid property
-- fail at all depths. Here is a contrived but illustrative example:
--
-- >prop_append1 :: [Bool] -> [Bool] -> Property
-- >prop_append1 xs ys = exists $ \zs -> zs == xs++ys
--
-- 'existsDeeperBy' transforms the depth bound by a given @'Depth' -> 'Depth'@ function:
--
-- >prop_append2 :: [Bool] -> [Bool] -> Property
-- >prop_append2 xs ys = existsDeeperBy (*2) $ \zs -> zs == xs++ys
existsDeeperBy :: (Show a, Serial a, Testable b) => (Depth->Depth) -> (a->b) -> Property
existsDeeperBy f = thereExists (series . f)

-- | Like 'existsDeeperBy', but additionally require the uniqueness of the
-- argument satisfying the predicate
exists1DeeperBy :: (Show a, Serial a, Testable b) => (Depth->Depth) -> (a->b) -> Property
exists1DeeperBy f = thereExists1 (series . f)

infixr 0 ==>

-- | The '==>' operator can be used to express a
-- restricting condition under which a property should hold. For example,
-- testing a propositional-logic module (see examples/logical), we might
-- define:
--
-- >prop_tautEval :: Proposition -> Environment -> Property
-- >prop_tautEval p e =
-- >  tautology p ==> eval p e
--
-- But here is an alternative definition:
--
-- >prop_tautEval :: Proposition -> Property
-- >prop_taut p =
-- >  tautology p ==> \e -> eval p e
--
-- The first definition generates p and e for each test, whereas the
-- second only generates e if the tautology p holds.
--
-- The second definition is far better as the test-space is
-- reduced from PE to T'+TE where P, T, T' and E are the numbers of
-- propositions, tautologies, non-tautologies and environments.
(==>) :: Testable a => Bool -> a -> Property
True ==>  x = Property (test x)
False ==> x = Property (const [nothing])
    where
    nothing = TestCase { result = Inappropriate, arguments = [] }