## Score model ----
scoreModel <- function(mod.obj, new.data, score.field = "Score", os.value = NULL, os.pct = NULL, pred.int = FALSE, int.vals = NULL, log.y = FALSE, ...) {
  UseMethod('scoreModel')
}

scoreModel.default <- function(mod.obj, new.data, score.field = "Score", os.value = NULL,
                               os.pct = NULL, ...){
  new.data <- matchLevels(new.data, getXlevels(mod.obj))
  y.levels <- getYlevels(mod.obj, new.data)
  if (class(mod.obj) == "earth" && is.null(mod.obj$glm.list)) {
    stop.Alteryx("Spline Models that did not use a GLM family cannot be scored")
  }
  if (is.null(y.levels)) {
    if(class(mod.obj)[1] %in% c("nnet.formula", "rpart")){
      scores <- data.frame(score = as.vector(predict(mod.obj, newdata = new.data)))
    } else {
      if (class(mod.obj)[1] == "gbm") {
        scores <- data.frame(score = as.vector(predict(mod.obj, newdata = new.data, type = "response", n.trees = mod.obj$best.trees)))
      } else {
        scores <- data.frame(score = as.vector(predict(mod.obj, newdata = new.data, type = "response")))
      }
    }
    names(scores) <- score.field
  } else {
    if (!is.null(os.value)) {
      if (length(y.levels) != 2) {
        AlteryxMessage("Adjusting for the oversampling of the target is only valid for a binary categorical variable, so the predicted probabilities will not be adjusted.", iType = 2, iPriority = 3)
        scores <- data.frame(predProb(mod.obj, newdata = the.data))
      } else {
        sample.pct <- samplePct(mod.obj, os.value, new.data)
        wr <- sample.pct/os.pct
        wc <- (100 - sample.pct)/(100 - os.pct)
        pred.prob <- predProb(mod.obj, new.data)[ , (1:2)[y.levels == os.value]]
        adj.prob <- (pred.prob/wr)/(pred.prob/wr + (1 - pred.prob)/wc)
        if (y.levels[1] == target.value) {
          scores <- data.frame(score1 = adj.prob, score2 = 1 - adj.prob)
        } else {
          scores <- data.frame(score1 = 1 - adj.prob, score2 = adj.prob)
        }
      }
    } else {
      scores <- data.frame(predProb(mod.obj, new.data))
    }
    names(scores) <- paste(score.field, "_", y.levels, sep = "")
  }
  scores
}

scoreModel.glm <- scoreModel.svyglm <- scoreModel.negbin <- scoreModel.default

scoreModel.lm <- function(mod.obj, new.data, score.field = "Score", pred.int = FALSE, int.vals = NULL, log.y = FALSE) {
  if (pred.int) {
    score <- as.data.frame(predict(mod.obj, newdata = new.data, level = 0.01*int.vals, interval = "predict"))
    if (log.y) {
      score$fit <- exp(score$fit)*(sum(exp(mod.obj$residuals))/length(mod.obj$residuals))
      score$lwr <- exp(score$lwr)*(sum(exp(mod.obj$residuals))/length(mod.obj$residuals))
      score$upr <- exp(score$upr)*(sum(exp(mod.obj$residuals))/length(mod.obj$residuals))
    }
    scores <- eval(parse(text = paste("data.frame(",score.field, "_fit = score$fit, ", score.field, "_lwr = score$lwr, ", score.field, "_upr = score$upr)", sep = "")))
  } else {
    score <- predict(mod.obj, newdata = new.data)
    if (log.y) {
      # The condition below checks to see if there are predicted values that
      # would imply machine infinity when expotentiated. If this is the case
      # a warning is given, and the smearing estimator is not applied. NOTE:
      # to make this code work nicely in non-Alteryx environments, the
      # AlteryxMessage call would need to be replaced with a message call
      if (max(score) > 709) {
        AlteryxMessage("The target variable does not appear to have been natural log transformed, no correction was applied.", iType = 2, iPriority = 3)
      } else {
        score <- exp(score)*(sum(exp(mod.obj$residuals))/length(mod.obj$residuals))
      }
    }
    scores <- eval(parse(text = paste("data.frame(", score.field, " = score)")))
  }
  scores
}

scoreModel.rxLogit <- function(mod.obj, new.data, score.field = "Score", os.value = NULL, os.pct = NULL) {
  new.data <- matchLevels(new.data, mod.obj$xlevels)
  pred.prob <- rxPredict(mod.obj, data = new.data, type = "response", predVarNames = "pred.prob")$pred.prob
  if (!is.null(os.value)) {
    target.value <- os.value
    num.target <- mod.obj$yinfo$counts[mod.obj$yinfo$levels == target.value]
    num.total <- sum(mod.obj$yinfo$counts)
    sample.pct <- 100*num.target / num.total
    wr <- sample.pct/os.pct
    wc <- (100 - sample.pct)/(100 - os.pct)
    if (mod.obj$yinfo$levels == target.value) {
      apr <- ((1 - pred.prob)/wr)/((1 - pred.prob)/wr + pred.prob/wc)
      scores <- data.frame(score1 = apr, score2 = 1 - apr)
    } else {
      adj.prob <- (pred.prob/wr)/(pred.prob/wr + (1 - pred.prob)/wc)
      scores <- data.frame(score1 = 1 - adj.prob, score2 = adj.prob)
    }
  } else {
    scores <- data.frame(score1 = 1 - pred.prob, score2 = pred.prob)
  }
  names(scores) <- eval(parse(text = paste('c("', score.field, '_', mod.obj$yinfo$levels[1], '", "', score.field, '_', mod.obj$yinfo$levels[2], '")', sep="")))
  scores
}

scoreModel.rxGlm <- function(mod.obj, new,data, score.field = "Score") {
  scores <- rxPredict(mod.obj, data = new.data, type = "response", predVarNames = "score")$score
  names(scores) <- score.field
  scores
}

scoreModel.rxLinMod <- function(mod.obj, new.data, score.field = "Score", pred.int = FALSE, int.vals = NULL, log.y = FALSE) {
  if (pred.int) {
    scores <- rxPredict(mod.obj, data = new.data, computeStdErrors = TRUE, interval = "prediction", confLevel = 0.01*int.vals, type = "response")
    scores <- scores[,-2]
    if (log.y)
      for (i in 1:3)
        scores[,i] <- exp(scores[[i]])*mod.obj$smearing.adj
    names(scores) <- paste(score.field, "_", c("fit", "lwr", "upr"), sep = "")
  } else {
    scores <- rxPredict(mod.obj, data = new.data, type = "response", predVarNames = "score")$score
    if (log.y) {
      if (is.null(mod.obj$smearing.adj)) {
        AlteryxMessage("The target variable does not appear to have been natrual log transformed, no correction was applied.", iType = 2, iPriority = 3)
      } else {
        scores <- exp(scores)*mod.obj$smearing.adj
      }
    }
  }
  scores
}

scoreModel.rxDTree <- function(mod.obj, new.data, score.field, os.value = NULL, os.pct = NULL) {
  new.data <- matchLevels(new.data, mod.obj$xlevels)
  # Classification trees
  if (!is.null(mod.obj$yinfo)) {
    scores <- rxPredict(mod.obj, data = new.data, type = "prob")
    if (class(mod.obj) == "rxDForest")
      scores <- scores[, -(ncol(scores))]
    if (!is.null(os.value)) {
      if (ncol(scores) != 2) {
        AlteryxMessage("Adjusting for the oversampling of the target is only valid for a binary categorical variable, so the predicted probabilities will not be adjusted.", iType = 2, iPriority = 3)
      } else {
        target.value <- os.value
        target.loc <- 2
        if (mod.obj$yinfo$levels[1] == target.value) {
          target.loc = 1
        }
        pred.prob <- scores[[target.loc]]
        num.target <- mod.obj$yinfo$counts[mod.obj$yinfo$levels == target.value]
        num.total <- sum(mod.obj$yinfo$counts)
        sample.pct <- 100*num.target / num.total
        wr <- sample.pct/os.pct
        wc <- (100 - sample.pct)/(100 - os.pct)
        if (mod.obj$yinfo$levels[1] == target.value) {
          apr <- ((1 - pred.prob)/wr)/((1 - pred.prob)/wr + pred.prob/wc)
          scores <- data.frame(score1 = apr, score2 = 1 - apr)
        } else {
          adj.prob <- (pred.prob/wr)/(pred.prob/wr + (1 - pred.prob)/wc)
          scores <- data.frame(score1 = 1 - adj.prob, score2 = adj.prob)
        }
      }
    }
    names(scores) <- paste(score.field, "_", mod.obj$yinfo$levels)
  } else { # Regression trees
    scores <- rxPredict(mod.obj, data = new.data, predVarNames = "score")$score
  }
  scores
}

scoreModel.rxDForest <- scoreModel.rxDTree

## End of the refactored Score code

