/***
  Copyright (C) 2010 Cosimo Cecchi <cosimoc@gnome.org>
  Copyright (C) 2013 Julián Unrrein <junrrein@gmail.com>

  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as published
  by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE. See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program. If not, see <http://www.gnu.org/licenses/>.

  Authors: Cosimo Cecchi <cosimoc@gnome.org>
           Julián Unrrein <junrrein@gmail.com>
***/

public class Marlin.ConnectServer.Operation : Gtk.MountOperation {

    private Marlin.ConnectServer.Dialog dialog;

    public Operation (Marlin.ConnectServer.Dialog dialog) {
    }
    
    private void fill_details_async_cb (Object source, AsyncResult result) {
        var dialog = source as Marlin.ConnectServer.Dialog;
    
        bool res = dialog.fill_details_async.end (result);
        
        if (res)
            reply (MountOperationResult.HANDLED);
        else
            reply (MountOperationResult.ABORTED);
    }

}