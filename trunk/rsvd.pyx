cimport numpy as np

import numpy as np
import sys
import pickle
import getopt

from time import time
from os.path import exists


globalAvgRating=3.603304257811724
randomNoise=0.005

"""The numpy data type of a rating array. 
"""
rating_t=np.dtype('H,I,B')


class RSVD(object):
    """A regularized singular value decomposition solver.
    
    The solver is used to compute the low-rank approximation of large partial
    matrices.

    To train a model (i.e. a factorization) use the following
    factory method:
    > model=RSVD.train(10,ratings,(17770,480189))

    Where ratings is a numpy record array of data type ('H,I,B'), which
    corresponds to (uint16,uint32,uint8). See `rsvd.rating_t`.

    To predict the rating of user i and movie j use:
    > model(j,i)
    
    """

    def __init__(self):
        pass

    def __getstate__(self):
        return {'num_users':self.num_users,
                'num_movies':self.num_movies,
                'factors':self.factors,
                'lr':self.lr,
                'reg':self.reg,
                'min_improvement':self.min_improvement,
                'max_epochs':self.max_epochs}
        
    def save(self,model_dir_path):
        """Saves the model to the given directory.
        The method raises a ValueError if the directory does not exist
        or if there is already a model in the directory.

        Parameters
        ----------
        model_dir_path : str
            The directory of the serialized model.
        
        """
        if exists(model_dir_path+'/v.arr') or \
           exists(model_dir_path+'/u.arr') or \
           exists(model_dir_path+'/model'):
            raise ValueError("There exists already a"+\
                             "model in %s" % model_dir_path) 

        if not exists(model_dir_path):
            raise ValueError("Directory %s does not exist." % model_dir_path)

        try:
            self.u.tofile(model_dir_path+"/u.arr")
            self.v.tofile(model_dir_path+"/v.arr")
            f=open(model_dir_path+"/model",'w+')
            pickle.dump(self,f)
            f.close()
        except AttributeError, e:
            print "Save Error: Model has not been trained.",e
        except IOError, e:
            print "IO Error: ",e

    @classmethod
    def load(cls,model_dir_path):
        """Loads the model from the given directory.

        Parameters
        ----------
        model_dir_path : str
            The directory that contains the model.

        Returns
        -------
        describe : 
        """
        f=file(model_dir_path+"/model")
        model=pickle.load(f)
        f.close()
        model.v=np.fromfile(model_dir_path+"/v.arr").\
                 reshape((model.num_users,model.factors))
        model.u=np.fromfile(model_dir_path+"/u.arr").\
                 reshape((model.num_movies,model.factors))
        return model

    def __call__(self,movie_id,user_id,user_map=None):
        """Predict the rating of user i and movie j.
        The prediction is the dot product of the user
        and movie factors, resp.
        The result is clipped in the range [1.0,5.0].
        
        Parameters
        ----------
        movie_id : int
            The raw movie id of the movie to be predicted.
        user_id : int
            The mapped user id of the user. 
            The mapping is based on the sorted order of user ids
            in the training set.

        Returns
        -------
        describe : float
            The predicted rating.
            
        """
        
        r=np.dot(self.u[movie_id-1],self.v[user_id])
        if r>5.0:
            r=5.0
        if r<1.0:
            r=1.0
        return r

    @classmethod
    def train(cls,factors,ratingsArray,dims,probeArray=None,\
                  maxEpochs=100,minImprovement=0.000001,\
                  learnRate=0.001,regularization=0.011,\
                  randomize=False):
        """Factorizes the partial rating matrix.

        If a validation set (probeArray) is given, early stopping is performed
        and training stops as soon as the relative improvement on the validation
        set is smaller than `minImprovement`.
        If `probeArray` is None, `maxEpochs` are performed.

	The complexity of the algorithm is O(n*k*m), where n is the number of
	non-missing values in R (i.e. the size of the `ratingArray`), k is the
	number of factors and m is the number of epochs to be performed. 

        Parameters
        ----------
        factors: int
            The number of latent variables. 
        ratingsArray : ndarray
            A numpy record array containing the ratings.E
            Each rating is a triple (uint16,uint32,uint8). 
        dims : tuple
            A tuple (numMovies,numUsers).
            It is used to determine the size of the
            matrix factors U and V.
        probeArray : ndarray
            A numpy record array containing the ratings
            of the validation set. (None)
        maxEpochs : int
            The maximum number of gradient descent iterations
            to perform. (100)
        minImprovement : float
            The minimum improvement in validation set error.
            This triggers early stopping. (0.000001)
        learnRate : float
            The step size in parameter space.
            Set with caution: if the lr is too high it might
            pass over (local) minima in the error function;
            if the `lr` is too low the algorithm hardly progresses. (0.001) 
        regularization : float
            The regularization term.
            It penalizes the magnitude of the parameters. (0.011)
        randomize : {True,False}
            Whether or not the ratingArray should be shuffeled. (False)

        Note
        ----
        It is assumed, that the `ratingsArray` is proper shuffeld. 
        If the randomize flag is set the `ratingArray` is shuffeled every 10th
        epoch. 

        """

        model=RSVD()
        model.num_movies,model.num_users=dims
        model.factors=factors
        model.lr=learnRate
        model.reg=regularization
        model.min_improvement=minImprovement
        model.max_epochs=maxEpochs

        initVal=np.sqrt(globalAvgRating/factors)

        rs=np.random.RandomState()
        # define the movie factors U

        model.u=rs.uniform(\
            -randomNoise,randomNoise, model.num_movies*model.factors)\
            .reshape(model.num_movies,model.factors)+initVal
        
        # define the user factors V
        model.v=rs.uniform(\
            -randomNoise,randomNoise, model.num_users*model.factors)\
            .reshape(model.num_users,model.factors)+initVal
        
        __trainModel(model,ratingsArray,probeArray,randomize=randomize)
        return model


def __trainModel(model,ratingsArray,probeArray,out=sys.stdout,randomize=False):
    """Trains the model on the given rating data.
    
    If `probeArray` is not None the error on the probe set is
    determined after each iteration and early stopping is done
    if the error on the probe set starts to increase.

    If `randomize` is True the `ratingsArray` is shuffled
    every 10th epoch.

    Parameters
    ----------
    model : RSVD
        The model to be trained.
    ratingsArray : ndarray
        The numpy record array holding the rating data.
    probeArray : ndarray
        The numpy record array holding the validation data.
    out : file
        File to which debug msg should be written. (default stdout)
    randomize : {True,False}
        Whether or not the training data should be shuffeled every
        10th iteration. 

    Notes
    -----

    * Shuffling may take a while.
    
    """
    cdef object[Rating] ratings=ratingsArray
    early_stopping=False
    cdef object[Rating] probeRatings=probeArray
    if probeArray is not None:
        early_stopping=True
    cdef int n=ratings.shape[0]
    cdef int nMovies=model.num_movies
    cdef int nUsers=model.num_users
    cdef int i,k,epochs=0
    cdef int K=model.factors
    cdef int max_epochs=model.max_epochs
    cdef np.uint16_t m=0
    cdef np.uint32_t u=0
    cdef np.double_t uTemp,vTemp,err,trainErr
    cdef np.double_t lr=model.lr
    cdef np.double_t reg=model.reg
    cdef double probeErr=0.0, oldProbeErr=0.0
    
    cdef np.ndarray U=model.u   
    cdef np.ndarray V=model.v
    
    cdef double *dataU=<double *>U.data
    cdef double *dataV=<double *>V.data
    
        
    out.write("########################################\n")
    out.write("             Factorizing                \n")
    out.write("########################################\n")
    out.write("factors=%d, epochs=%d, lr=%f, reg=%f\n" % (K,max_epochs,lr,reg))
    out.flush()
    if early_stopping:
        oldProbeErr=probe(<Rating *>&(probeRatings[0]),\
                          dataU,dataV,K,probeRatings.shape[0])
        out.write("Init PRMSE: %f\n" % oldProbeErr)
        out.flush()

    trainErr=probe(<Rating *>&(ratings[0]), dataU, dataV,K,n)
    out.write("Init TRMSE: %f\n" % trainErr)
    out.write("----------------------------------------\n")
    out.write("epoche\ttrain err\tprobe err\telapsed time\n")
    out.flush()
    for epoch from 0 <= epoch < max_epochs:
        t1=time()
        if randomize and epoch%10==0:
            out.write("Shuffling training data\t")
            out.flush()
            np.random.shuffle(ratings)
            out.write("Done\n")
        trainErr=train(<Rating *>&(ratings[0]), dataU, \
                            dataV, K,n, reg,lr)

        if early_stopping:
            probeErr=probe(<Rating *>&(probeRatings[0]),dataU, \
                                dataV,K,probeRatings.shape[0])
            if oldProbeErr-probeErr < model.min_improvement:
                out.write("Early stopping\nRelative improvement %f\n" \
                          % (oldProbeErr-probeErr))
                break
            oldProbeErr=probeErr
        out.write("%d\t%f\t%f\t%f\n"%(epoch,trainErr,probeErr,time()-t1))
        out.flush()

# The Rating struct. 
cdef struct Rating:
    np.uint16_t movieID
    np.uint32_t userID
    np.uint8_t rating

cdef double predict(int uOffset,int vOffset, \
                        double *dataU, double *dataV, \
                        int factors):
    """Predict the rating of user i and movie j by first computing the
    dot product of the user and movie factors. 
    """
    cdef double pred=0.0
    cdef int k=0
    for k from 0<=k<factors:
        pred+=dataU[uOffset+k] * dataV[vOffset+k]
    return pred

cdef double predictClip(int uOffset,int vOffset, \
                        double *dataU, double *dataV, \
                        int factors):
    """Predict the rating of user i and movie j by first computing the
    dot product of the user and movie factors. Finally, the prediction
    is clipped into the range [1,5].
    """
    cdef double pred=0.0
    cdef int k=0
    for k from 0<=k<factors:
        pred+=dataU[uOffset+k] * dataV[vOffset+k]
    if pred>5.0:
        pred=5.0
    if pred<1.0:
        pred=1.0
    return pred


cdef double train(Rating *ratings, \
                            double *dataU, double *dataV, \
                            int factors, int n, double reg,double lr):
    """The inner loop of the factorization procedure.

    Iterate through the rating array: for each rating compute
    the gradient with respect to the current parameters
    and update the movie and user factors, resp. 
    """
    cdef int k=0,i=0,uOffset=0,vOffset=0
    cdef int user=0
    cdef int movie=0
    cdef Rating r
    cdef double uTemp=0.0,vTemp=0.0,err=0.0,sumSqErr=0.0
    for i from 0<=i<n:
        r=ratings[i]
        user=r.userID
        movie=r.movieID-1  
        uOffset=movie*factors
        vOffset=user*factors
        err=<double>r.rating - \
            predict(uOffset,vOffset, dataU, dataV, factors)
        sumSqErr+=err*err;
        for k from 0<=k<factors:
            uTemp = dataU[uOffset+k]
            vTemp = dataV[vOffset+k]
            dataU[uOffset+k]+=lr*(err*vTemp-reg*uTemp)
            dataV[vOffset+k]+=lr*(err*uTemp-reg*vTemp)
    return np.sqrt(sumSqErr/n)

cdef double probe(Rating *probeRatings, double *dataU, \
                      double *dataV, int factors, int numRatings):
    cdef int i,uOffset,vOffset
    cdef unsigned int user
    cdef unsigned short movie
    cdef Rating r
    cdef double err,sumSqErr=0.0
    for i from 0<=i<numRatings:
        r=probeRatings[i]
        user=r.userID
        movie=r.movieID-1
        uOffset=movie*factors
        vOffset=user*factors
        err=(<double>r.rating) - predictClip(uOffset,vOffset, dataU,dataV,factors)
        sumSqErr+=err*err
    return np.sqrt(sumSqErr/numRatings)


