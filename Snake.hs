{-# OPTIONS_GHC -Wall #-}

import Data.List

import System.IO
import System.Timeout
import System.Random
import System.Console.ANSI

import Control.Concurrent
import Control.Concurrent.Async
import Control.Monad.Loops
import Control.Applicative

type Vector = (Int, Int)

data State = State {
    board :: (Int, Int),
    snake :: [Vector],
    fruit :: Maybe (Vector, StdGen),
    move  :: Maybe Vector
} deriving Show

main :: IO State
main = clearScreen
    >> initialState
    >>= (iterateUntilM gameOver step)

oneSecond :: Int
oneSecond = (10 :: Int) ^ (6 :: Int)

sampleLength :: Int
sampleLength = oneSecond `div` 4

initialState :: IO State
initialState = getStdGen
    >>= \stdGen -> return State {
        board = (20, 26),
        snake = [(4, 0), (3, 0), (2, 0), (1, 0), (0, 0)],
        fruit = randomElem (concat (buildBoard (20, 26))) stdGen,
        move  = Just (1, 0)
    }

randomElem :: [a] -> StdGen -> Maybe (a, StdGen)
randomElem [] _  = Nothing
randomElem xs inputStdGen  = Just (element, stdGen)
    where indexStdGenTuple = randomR (0, length xs - 1) inputStdGen
          index            = fst indexStdGenTuple
          stdGen           = snd indexStdGenTuple
          element          = xs !! index

newFruit :: State -> Maybe (Vector, StdGen)
newFruit (State { fruit = Nothing }) = Nothing
newFruit state@(State { fruit = Just (_, stdGen) })
    = randomElem validPositions stdGen
        where allPositions   = concat $ buildBoard $ board state
              validPositions = allPositions \\ snake state

step :: State -> IO State
step state = sample sampleLength getInput
    >>= \ inputMove ->
        displayState $ updateState state (vectorFromChar inputMove)

displayState :: State -> IO State
displayState state = setCursorPosition 0 0
    >> putStr  ((render state) ++ "Length of snake: " ++ (show . length $ snake state))
    >> return state

vectorFromChar :: Maybe Char -> Maybe Vector
vectorFromChar (Just 'w') = Just ( 0, -1)
vectorFromChar (Just 'a') = Just (-1,  0)
vectorFromChar (Just 's') = Just ( 0,  1)
vectorFromChar (Just 'd') = Just ( 1,  0)
vectorFromChar _          = Nothing

getInput :: IO Char
getInput = hSetEcho stdin False
    >> hSetBuffering stdin NoBuffering
    >> getChar

gameOver :: State -> Bool
gameOver (State { snake = [] }) = True
gameOver (State {
    board = boardSize,
    snake = (snakeHead@(snakeHeadX, snakeHeadY):snakeBody)
})
    | snakeHeadX >= fst boardSize || snakeHeadX < 0 = True
    | snakeHeadY >= snd boardSize || snakeHeadY < 0 = True
    | snakeHead `elem` snakeBody                = True
    | otherwise                                 = False

render :: State -> String
render state
    = unlines $ map (\row -> "█" ++ row ++ "█") $ [renderFirstRow state first_row] ++ map (renderRow state) rows ++ [renderLastRow state last_row]
    where
      first_row = [(x, 0) | x <- [0 .. sizex - 1]]
      rows = [[(x, y) | x <- [0 .. sizex - 1]] | y <- [1, 3 .. sizey - 3] ]
      last_row = [(x, sizey-1) | x <- [0 .. sizex - 1]]
      (sizex, sizey) = board state

renderFirstRow :: State -> [Vector] -> String
renderFirstRow state positions = map (characterForTopPosition state) positions

characterForTopPosition :: State -> Vector -> Char
characterForTopPosition state (x, 0)
  | (x, 0) `elem` snake state                = '█'
  | fruit state `fruitPositionEquals` (x, 0) = '█'
  | otherwise                                = '▀'

renderLastRow :: State -> [Vector] -> String
renderLastRow state positions = map (characterForBottomPosition state) positions

characterForBottomPosition :: State -> Vector -> Char
characterForBottomPosition state (x, y)
  | (x, y) `elem` snake state                = '█'
  | fruit state `fruitPositionEquals` (x, y) = '█'
  | otherwise                                = '▄'


renderRow :: State -> [Vector] -> String
renderRow state = map (characterForPosition state)

characterForPosition :: State -> Vector -> Char
characterForPosition state (x,y)
    | and $ map (`elem` snake state) [(x, y), (x, y+1)] = '█'
    | (x, y) `elem` snake state                  = '▀'
    | (x, y+1) `elem` snake state                = '▄'
    | fruit state `fruitPositionEquals` (x, y)   = '▀'
    | fruit state `fruitPositionEquals` (x, y+1) = '▄'
    | otherwise                                  = ' '

fruitPositionEquals :: Maybe (Vector, StdGen) -> Vector -> Bool
fruitPositionEquals (Just (position, _)) vector = position == vector
fruitPositionEquals _ _                         = False

snakeHasFruitInMouth :: State -> Bool
snakeHasFruitInMouth state
    = fruit state `fruitPositionEquals` head (snake state)

buildBoard :: (Int, Int) -> [[(Int, Int)]]
buildBoard (sizex, sizey)
    = [[(x, y) | x <- [0 .. sizex - 1]] | y <- reverse [0 .. sizey - 1]]

updateState :: State -> Maybe Vector -> State
updateState state inputMove
    = updateFruit $ updateSnake $ updateMove state inputMove

updateMove :: State -> Maybe Vector -> State
updateMove state@(State { move = Just vector }) inputMove@(Just inputVector)
    | inputVector == vectorOpposite vector
        = state
    | otherwise
        = state { move = inputMove <|> move state }
updateMove state _ = state

updateSnake :: State -> State
updateSnake = updateSnakeTail . updateSnakeHead

updateFruit :: State -> State
updateFruit state
    | snakeHasFruitInMouth state = state { fruit = newFruit state }
    | otherwise                  = state

updateSnakeHead :: State -> State
updateSnakeHead state@(State { move = (Just vector) })
    = state { snake = head (snake state) `vectorAdd` vector : snake state }
updateSnakeHead state = state

updateSnakeTail :: State -> State
updateSnakeTail state
    | snakeHasFruitInMouth state = state
    | otherwise                  = state { snake = init $ snake state }

vectorAdd :: Vector -> Vector -> Vector
vectorAdd (x1, y1) (x2, y2) = (x1 + x2, y1 + y2)

vectorOpposite :: Vector -> Vector
vectorOpposite (x, y) = (-x, -y)

sample :: Int -> IO a -> IO (Maybe a)
sample n f
    | n <  0    = fmap Just f
    | n == 0    = return Nothing
    | otherwise =
        concurrently (timeout n f) (threadDelay n)
            >>= \ (result, _) -> return result
