<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 *
 * @copyright   2001-2006 by moleSoftware GmbH
 * @copyright   2006-2010 by ispCP | http://isp-control.net
 * @copyright   2010-2011 by i-msCP | http://i-mscp.net
 * @version     SVN: $Id$
 * @link        http://i-mscp.net
 * @author      ispCP Team
 * @author      i-MSCP Team
 *
 * @license
 * The contents of this file are subject to the Mozilla Public License
 * Version 1.1 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * The Original Code is "VHCS - Virtual Hosting Control System".
 *
 * The Initial Developer of the Original Code is moleSoftware GmbH.
 * Portions created by Initial Developer are Copyright (C) 2001-2006
 * by moleSoftware GmbH. All Rights Reserved.
 *
 * Portions created by the ispCP Team are Copyright (C) 2006-2010 by
 * isp Control Panel. All Rights Reserved.
 *
 * Portions created by the i-MSCP Team are Copyright (C) 2010-2011 by
 * i-MSCP a internet Multi Server Control Panel. All Rights Reserved.
 */

/************************************************************************************
 * Script functions
 */

/**
 * Saves layout.
 *
 * @return void
 */
/* Not used for now
function save_layout()
{
    global $theme_color;

    if (isset($_POST['uaction']) && $_POST['uaction'] === 'save_layout') {

        $user_id = $_SESSION['user_id'];
        $user_layout = $_POST['def_layout'];

        $query = "UPDATE `user_gui_props` SET `layout` = ? WHERE `user_id` = ?";
        exec_query($query, array($user_layout, $user_id));

        $theme_color = $user_layout;
        $_SESSION['user_theme_color'] = $user_layout;
    }
}
*/

/************************************************************************************
 * Main script
 */

// Include core library
require 'imscp-lib.php';

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onResellerScriptStart);

check_login(__FILE__);

/** @var $cfg iMSCP_Config_Handler_File */
$cfg = iMSCP_Registry::get('config');

$tpl = new iMSCP_pTemplate();
$tpl->define_dynamic(array('page' => $cfg->RESELLER_TEMPLATE_PATH . '/settings_layout.tpl',
                          'page_message' => 'page',
                          'logged_from' => 'page',
                          //'def_layout' => 'page',
                          'logo_remove_button' => 'page'));

// Not used for now
//save_layout();

/**
 * Dispatches request
 */
if(isset($_POST['uaction'])) {
    if($_POST['uaction'] == 'updateIspLogo') {
        layout_updateUserLogo() ?:
            set_page_message(tr('Logo successfully updated.'), 'success');
    } elseif($_POST['uaction'] == 'deleteIspLogo') {
        layout_deleteUserLogo() ?:
            set_page_message(tr('Logo successfully removed.'), 'success');
    } else {
        set_page_message(tr('Unknown action: %s', tohtml($_POST['uaction'])), 'error');
    }
}

// Not used for now
//gen_def_layout($tpl, $cfg->USER_INITIAL_THEME);

$ispLogo = layout_getUserLogo(false);

if (layout_isUserLogo($ispLogo)) {
    $tpl->parse('LOGO_REMOVE_BUTTON', '.logo_remove_button');
} else {
    $tpl->assign('LOGO_REMOVE_BUTTON', '');
}

$tpl->assign(array(
                  'TR_PAGE_TITLE' => tr('i-MSCP - Reseller / Layout'),
                  'THEME_COLOR_PATH' => "../themes/{$cfg->USER_INITIAL_THEME}",
                  'ISP_LOGO' => layout_getUserLogo(),
                  'OWN_LOGO' => $ispLogo,
                  'THEME_CHARSET' => tr('encoding'),
                  'TR_GENERAL_INFO' => tr('General information'),
                  'TR_LAYOUT_SETTINGS' => tr('Layout settings'),
                  //'TR_INSTALLED_LAYOUTS' => tr('Installed layouts'),
                  //'TR_LAYOUT_NAME' => tr('Layout name'),
                  //'TR_LAYOUT' => tr('Layout'),
                  //'TR_DEFAULT' => tr('default'),
                  //'TR_YES' => tr('yes'),
                  //'TR_SAVE' => tr('Save'),
                  'TR_UPLOAD_LOGO' => tr('Upload logo'),
                  'TR_LOGO_FILE' => tr('Logo file'),
                  'TR_UPLOAD' => tr('Upload'),
                  'TR_REMOVE' => tr('Remove'),
                  //'TR_CHOOSE_DEFAULT_LAYOUT' => tr('Choose default layout')
             ));

gen_reseller_mainmenu($tpl, $cfg->RESELLER_TEMPLATE_PATH . '/main_menu_general_information.tpl');
gen_reseller_menu($tpl, $cfg->RESELLER_TEMPLATE_PATH . '/menu_general_information.tpl');
gen_logged_from($tpl);
generatePageMessage($tpl);

$tpl->parse('PAGE', 'page');

iMSCP_Events_Manager::getInstance()->dispatch(
    iMSCP_Events::onResellerScriptEnd, new iMSCP_Events_Response($tpl));

$tpl->prnt();

unsetMessages();
