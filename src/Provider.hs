module Provider
 ( FakeProvider()
 , activeInteractions
 , verifiedInteractions
 , addInteraction
 , setInteractions
 , resetInteractions
 , findInteractionForRequest
 , recordRequest
 , verifyInteractions
 , getVerifiedInteractions
 , FakeProviderState
 , newFakeProviderState
 , runDebug
 ) where

import Control.Concurrent.STM
import Control.Monad.State

import qualified Data.List as L
import qualified Pact as P

data FakeProvider = FakeProvider
 { activeInteractions :: [P.Interaction]
 , matchedInteractions :: [P.Interaction]
 , verifiedInteractions :: [P.Interaction]
 , mismatchedRequests :: [P.Request]
 } deriving (Show)

initialFakeProvider :: FakeProvider
initialFakeProvider = FakeProvider [] [] [] []

addInteraction :: P.Interaction -> State FakeProvider ()
addInteraction i = modify $ \p -> p { activeInteractions = (i : activeInteractions p) }

setInteractions :: [P.Interaction] -> State FakeProvider ()
setInteractions is = modify $ \p -> p { activeInteractions = is }

resetInteractions :: State FakeProvider ()
resetInteractions = modify $ \p -> p { activeInteractions = [], mismatchedRequests = [], matchedInteractions = [] }

findInteractionForRequest :: P.Request -> State FakeProvider (Maybe P.Interaction)
findInteractionForRequest req = gets $ \p -> L.find (\i -> P.validateRequest (P.interactionRequest i) req == []) $ activeInteractions p

addInteractionMatch :: P.Interaction -> State FakeProvider ()
addInteractionMatch i = modify $ \p -> p
 { matchedInteractions = (i : matchedInteractions p)
 , verifiedInteractions = (i : verifiedInteractions p)
 }

addMismatchedRequest :: P.Request -> State FakeProvider ()
addMismatchedRequest i = modify $ \p -> p { mismatchedRequests = (i : mismatchedRequests p) }

recordRequest :: P.Request -> State FakeProvider (Maybe P.Interaction)
recordRequest req = do
  maybeInteraction <- findInteractionForRequest req
  case maybeInteraction of
    Just interaction -> addInteractionMatch interaction
    Nothing -> addMismatchedRequest req
  return maybeInteraction

verifyInteractions :: State FakeProvider Bool
verifyInteractions = gets $ \p -> (length $ mismatchedRequests p) == 0 && (length $ matchedInteractions p) == (length $ activeInteractions p)

getVerifiedInteractions :: State FakeProvider [P.Interaction]
getVerifiedInteractions = gets verifiedInteractions

-- Transactions

type FakeProviderState = TVar FakeProvider
type FakeProviderTX a = FakeProviderState -> STM (a, FakeProvider)

newFakeProviderState :: IO FakeProviderState
newFakeProviderState = newTVarIO initialFakeProvider

liftTX :: State FakeProvider a -> FakeProviderTX a
liftTX m v = do
  (a, s) <- runState m <$> readTVar v
  writeTVar v s
  return (a, s)  

runDebugTX :: FakeProviderState -> FakeProviderTX a -> IO a
runDebugTX fps tx = atomically (tx fps) >>= \(a, s) -> print s >> return a

runDebug :: FakeProviderState -> State FakeProvider a -> IO a
runDebug fps = runDebugTX fps . liftTX
