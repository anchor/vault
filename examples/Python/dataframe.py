#!/usr/bin/env python

'''Thin wrapper on the DataFrame protobuf
'''
from DataFrame_pb2 import DataFrame

# Add a single property to the DataFrame class to return the value of the frame
# that is dependent on the frame itself
#
# We would subclass DataFrame but compiler's crazy use of introspection breaks
# subclassing
def _dataframe_value(frame):
    '''return the value of a DataFrame, regardless of type
    '''
    if frame.payload == frame.EMPTY:
        return None
    elif frame.payload == frame.NUMBER:
        return frame.value_numeric
    elif frame.payload == frame.REAL:
        return frame.value_measurement
    elif frame.payload == frame.TEXT:
        return frame.value_textual
    elif frame.payload == frame.BINARY:
        return frame.value_blob
    else:
        raise TypeError("Unknown type")
if 'value' not in DataFrame.__slots__: DataFrame.__slots__.append('value')
DataFrame.value = property(_dataframe_value)

# Use  dicts in a less painfully than by hand every time
def _dataframe_sourcedict_set(frame, d):
	'''extend list of sources from a dict'''
	for k,v in d.items(): frame.source.add(field=k,value=v)
def _dataframe_sourcedict_get(frame):
	'''return sources as a dict'''
	return dict((t.field,t.value) for t in frame.source)
if 'sourcedict' not in DataFrame.__slots__: DataFrame.__slots__.append('sourcedict')
DataFrame.sourcedict = property(_dataframe_sourcedict_get,_dataframe_sourcedict_set)
