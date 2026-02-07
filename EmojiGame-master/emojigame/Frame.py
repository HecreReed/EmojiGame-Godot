import wx


class Frame(wx.Frame):
    def __init__(self, title, pos, size, parent=None, id=-1):
        wx.Frame.__init__(self, parent, id, title, pos, size)
